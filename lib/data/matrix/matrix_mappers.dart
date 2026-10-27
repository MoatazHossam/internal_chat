import 'package:matrix/matrix.dart';

import '../../domain/ids.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import 'outbox/forward_content.dart';
import 'outbox/outbox_entry.dart';

const _i18n = MatrixDefaultLocalizations();

const _voiceMarker = 'org.matrix.msc3245.voice';
const _extensibleAudio = 'org.matrix.msc1767.audio';

Conversation mapRoom(Room room) {
  final me = room.client.userID;
  final last = room.lastEvent;
  final showLast = last != null && isTimelineItem(last);
  final inviteEvent = room.membership == Membership.invite && me != null
      ? room.getState(EventTypes.RoomMember, me)
      : null;

  return Conversation(
    id: ConversationId(room.id),
    title: room.getLocalizedDisplayname(_i18n),
    kind: room.isDirectChat ? ConversationKind.direct : ConversationKind.group,
    isEncrypted: room.encrypted,
    lastMessagePreview: showLast ? _bodyOf(last, kindOf(last)) : null,
    lastMessageKind: showLast ? kindOf(last) : null,
    lastMessageSenderName: showLast
        ? last.senderFromMemoryOrFallback.calcDisplayname()
        : null,
    lastMessageIsOwn: showLast && last.senderId == me,
    lastActivityAt: room.latestEventReceivedTime,
    unreadCount: room.notificationCount,
    participantCount: room.summary.mJoinedMemberCount,
    isTyping: room.typingUsers.any((user) => user.id != me),
    isInvite: room.membership == Membership.invite,
    invitedBy: inviteEvent == null
        ? null
        : room
              .unsafeGetUserFromMemoryOrFallback(inviteEvent.senderId)
              .calcDisplayname(),
  );
}

/// Maps a timeline to domain messages, newest first.
List<ChatMessage> mapTimeline(Timeline timeline) {
  final room = timeline.room;
  final me = room.client.userID;
  final events = timeline.events;

  // Receipts mean "read up to here". Everything at or below the newest event
  // that another member has a receipt on counts as read. In groups that is
  // "read by at least one other member". Matrix has no delivery receipts.
  final readFromIndex = events.indexWhere(
    (event) => event.receipts.any((receipt) => receipt.user.id != me),
  );

  final messages = <ChatMessage>[];
  for (var i = 0; i < events.length; i++) {
    final event = events[i];
    if (!isTimelineItem(event)) continue;
    final readByOthers = readFromIndex >= 0 && i >= readFromIndex;
    messages.add(mapEvent(event, timeline, readByOthers: readByOthers));
  }
  return messages;
}

ChatMessage mapEvent(
  Event event,
  Timeline timeline, {
  required bool readByOthers,
}) {
  final room = event.room;
  final isOwn = event.senderId == room.client.userID;
  final display = event.getDisplayEvent(timeline);
  final kind = kindOf(display);
  final failed = event.status.isError;
  final status = failed
      ? MessageDeliveryStatus.failed
      : event.status.isSending
      ? MessageDeliveryStatus.pending
      : (isOwn && readByOthers)
      ? MessageDeliveryStatus.read
      : MessageDeliveryStatus.sent;

  final replyId = event.inReplyToEventId();
  final replyEvent = replyId == null
      ? null
      : timeline.events.where((e) => e.eventId == replyId).firstOrNull;
  final replyDisplay = replyEvent?.getDisplayEvent(timeline);
  final transactionId = event.transactionId;

  return ChatMessage(
    id: event.eventId,
    conversationId: ConversationId(room.id),
    senderId: UserId(event.senderId),
    senderDisplayName: event.senderFromMemoryOrFallback.calcDisplayname(),
    body: _bodyOf(display, kind),
    sentAt: event.originServerTs,
    kind: kind,
    isOwn: isOwn,
    status: status,
    // Only local echoes left by an earlier version of the app fail here;
    // current sends live in the outbox. Their attachments were not kept.
    failureReason: !failed
        ? null
        : display.hasAttachment
        ? SendFailureReason.notResendable
        : SendFailureReason.server,
    localId: isOwn && transactionId != null
        ? LocalMessageId(transactionId)
        : null,
    edited: event.hasAggregatedEvents(timeline, RelationshipTypes.edit),
    forwarded: display.content[forwardedMarker] == true,
    canEdit: isOwn && kind == MessageKind.text && event.status.isSent,
    canDelete: kind != MessageKind.deleted && (isOwn || event.canRedact),
    reactions: _reactionsOf(event, timeline),
    replyToId: replyId,
    replyToSenderName: replyEvent?.senderFromMemoryOrFallback.calcDisplayname(),
    replyToBody: replyDisplay == null
        ? null
        : _bodyOf(replyDisplay, kindOf(replyDisplay)),
    replyToKind: replyDisplay == null ? null : kindOf(replyDisplay),
    attachmentName: _attachmentName(display, kind),
    attachmentMimeType: display.hasAttachment
        ? display.attachmentMimetype
        : null,
    attachmentSizeBytes: display.infoMap.tryGet<int>('size'),
    attachmentDurationMs: _durationMs(display),
  );
}

/// Outbox entries as messages, newest first. They stay in the list (as
/// pending, waiting for network or failed) until sent.
List<ChatMessage> mapOutbox(
  Iterable<OutboxEntry> entries,
  Timeline timeline, {
  required bool online,
  required bool Function(String txnId) isInFlight,
}) {
  final room = timeline.room;
  final me = room.client.userID ?? '';
  final myName = room.unsafeGetUserFromMemoryOrFallback(me).calcDisplayname();
  final messages = [
    for (final entry in entries)
      _mapEntry(
        entry,
        timeline,
        senderName: myName,
        online: online,
        inFlight: isInFlight(entry.txnId),
      ),
  ];
  messages.sort((a, b) => b.sentAt.compareTo(a.sentAt));
  return messages;
}

ChatMessage _mapEntry(
  OutboxEntry entry,
  Timeline timeline, {
  required String senderName,
  required bool online,
  required bool inFlight,
}) {
  final forwarded = entry.forwardContent;
  final content = forwarded ?? entry.payload;
  final info = forwarded?['info'];
  final infoMap = info is Map ? info : const {};
  final kind = switch (entry.kind) {
    OutboxKind.text => MessageKind.text,
    OutboxKind.voice => MessageKind.voice,
    OutboxKind.file => _kindOfMime(entry.mimeType),
    OutboxKind.forward => switch (forwarded?['msgtype']) {
      MessageTypes.Image => MessageKind.image,
      MessageTypes.Audio =>
        forwarded?[_voiceMarker] != null
            ? MessageKind.voice
            : MessageKind.audio,
      MessageTypes.File || MessageTypes.Video => MessageKind.file,
      _ => MessageKind.text,
    },
  };

  final replyId = entry.replyTo;
  final replyEvent = replyId == null
      ? null
      : timeline.events.where((e) => e.eventId == replyId).firstOrNull;
  final replyDisplay = replyEvent?.getDisplayEvent(timeline);

  final status = switch (entry.state) {
    OutboxState.failed => MessageDeliveryStatus.failed,
    OutboxState.queued
        when !inFlight &&
            (!online || entry.lastError == SendErrorClass.network) =>
      MessageDeliveryStatus.waitingForNetwork,
    OutboxState.queued => MessageDeliveryStatus.pending,
  };

  return ChatMessage(
    id: entry.txnId,
    conversationId: ConversationId(entry.roomId),
    senderId: UserId(entry.userId),
    senderDisplayName: senderName,
    body: kind == MessageKind.text ? (content['body'] as String? ?? '') : '',
    sentAt: entry.createdAt,
    kind: kind,
    isOwn: true,
    status: status,
    failureReason: entry.state == OutboxState.failed
        ? _failureReason(entry.lastError)
        : null,
    localId: LocalMessageId(entry.txnId),
    forwarded: entry.kind == OutboxKind.forward,
    canDelete: !inFlight,
    replyToId: replyId,
    replyToSenderName: replyEvent?.senderFromMemoryOrFallback.calcDisplayname(),
    replyToBody: replyDisplay == null
        ? null
        : _bodyOf(replyDisplay, kindOf(replyDisplay)),
    replyToKind: replyDisplay == null ? null : kindOf(replyDisplay),
    attachmentName: kind == MessageKind.text
        ? null
        : entry.fileName ??
              forwarded?['filename'] as String? ??
              forwarded?['body'] as String?,
    attachmentMimeType: entry.mimeType ?? infoMap['mimetype'] as String?,
    attachmentSizeBytes:
        entry.payload['size'] as int? ?? infoMap['size'] as int?,
    attachmentDurationMs: entry.durationMs ?? infoMap['duration'] as int?,
  );
}

MessageKind _kindOfMime(String? mimeType) {
  final type = mimeType?.toLowerCase() ?? '';
  if (type.startsWith('image/')) return MessageKind.image;
  if (type.startsWith('audio/')) return MessageKind.audio;
  return MessageKind.file;
}

SendFailureReason _failureReason(SendErrorClass? error) => switch (error) {
  SendErrorClass.notAllowed => SendFailureReason.notAllowed,
  SendErrorClass.tooLarge => SendFailureReason.tooLarge,
  SendErrorClass.notEncrypted => SendFailureReason.notEncrypted,
  SendErrorClass.encryptionUnavailable =>
    SendFailureReason.encryptionUnavailable,
  SendErrorClass.rejected => SendFailureReason.rejected,
  SendErrorClass.uncertain => SendFailureReason.uncertain,
  _ => SendFailureReason.server,
};

/// Whether [event] gets its own item in the message list. State changes,
/// reactions, edits, redactions and verification events do not.
bool isTimelineItem(Event event) {
  if (event.stateKey != null) return false;
  if (event.type == EventTypes.Reaction || event.type == EventTypes.Redaction) {
    return false;
  }
  if (event.type.startsWith('m.key.verification.')) return false;
  // Edits are folded into the message they replace.
  if (event.relationshipType == RelationshipTypes.edit) return false;
  return true;
}

MessageKind kindOf(Event event) {
  if (event.redacted) return MessageKind.deleted;
  if (event.type == EventTypes.Encrypted) return MessageKind.undecryptable;
  if (event.type == EventTypes.Sticker) return MessageKind.image;
  if (event.type != EventTypes.Message) return MessageKind.unsupported;
  return switch (event.messageType) {
    MessageTypes.Text ||
    MessageTypes.Notice ||
    MessageTypes.Emote => MessageKind.text,
    MessageTypes.Image => MessageKind.image,
    MessageTypes.Audio =>
      event.content[_voiceMarker] != null
          ? MessageKind.voice
          : MessageKind.audio,
    MessageTypes.File || MessageTypes.Video => MessageKind.file,
    MessageTypes.BadEncrypted => MessageKind.undecryptable,
    _ => MessageKind.unsupported,
  };
}

String _bodyOf(Event event, MessageKind kind) {
  // Undecryptable events carry the decryption error as their body, and
  // unsupported or deleted ones have nothing useful to show. The UI renders
  // a localized placeholder for those kinds instead.
  if (kind != MessageKind.text) return '';
  return event.calcLocalizedBodyFallback(
    _i18n,
    hideReply: true,
    hideEdit: true,
    plaintextBody: true,
  );
}

String? _attachmentName(Event event, MessageKind kind) {
  if (!event.hasAttachment) return null;
  return event.content.tryGet<String>('filename') ??
      event.content.tryGet<String>('body');
}

int? _durationMs(Event event) {
  if (event.messageType != MessageTypes.Audio) return null;
  return event.infoMap.tryGet<int>('duration') ??
      event.content
          .tryGetMap<String, Object?>(_extensibleAudio)
          ?.tryGet<int>('duration');
}

List<Reaction> _reactionsOf(Event event, Timeline timeline) {
  final me = event.room.client.userID;
  final counts = <String, int>{};
  final mine = <String>{};
  for (final reaction in event.aggregatedEvents(
    timeline,
    RelationshipTypes.reaction,
  )) {
    if (reaction.redacted) continue;
    final key = reaction.content
        .tryGetMap<String, Object?>('m.relates_to')
        ?.tryGet<String>('key');
    if (key == null) continue;
    counts[key] = (counts[key] ?? 0) + 1;
    if (reaction.senderId == me) mine.add(key);
  }
  return [
    for (final entry in counts.entries)
      Reaction(
        key: entry.key,
        count: entry.value,
        includesMe: mine.contains(entry.key),
      ),
  ];
}
