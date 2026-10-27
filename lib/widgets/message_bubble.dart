import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/chat_message.dart';
import '../utilities/failure_messages.dart';
import '../utilities/message_labels.dart';
import 'voice_note_player.dart';

typedef AttachmentLoader = Future<Uint8List> Function({bool thumbnail});

/// A WhatsApp-style message bubble.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.showSenderName = false,
    this.highlightQuery,
    this.isCurrentMatch = false,
    this.loadAttachment,
    this.onOpenAttachment,
    this.onReactionTap,
  });

  final ChatMessage message;

  /// Show sender name above the body (used in group chats for incoming msgs).
  final bool showSenderName;

  /// When set, occurrences of this text within [message.body] are
  /// highlighted (used by in-conversation search).
  final String? highlightQuery;

  /// Whether this bubble is the currently focused search match.
  final bool isCurrentMatch;

  final AttachmentLoader? loadAttachment;
  final VoidCallback? onOpenAttachment;
  final void Function(String key)? onReactionTap;

  static const _senderPalette = <Color>[
    Color(0xFFE57373),
    Color(0xFF81C784),
    Color(0xFF64B5F6),
    Color(0xFFFFB74D),
    Color(0xFFBA68C8),
    Color(0xFF4DD0E1),
    Color(0xFFF06292),
  ];

  Color _senderColor(String senderId) {
    final index =
        senderId.codeUnits.fold(0, (a, b) => a + b) % _senderPalette.length;
    return _senderPalette[index];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFromMe = message.isOwn;
    final mutedColor = isDark ? Colors.white54 : Colors.black45;

    final Color bubbleColor;
    if (isFromMe) {
      bubbleColor = isDark ? const Color(0xFF005C4B) : const Color(0xFFDCF8C6);
    } else {
      bubbleColor = isDark ? const Color(0xFF1E2D35) : Colors.white;
    }

    return Align(
      alignment: isFromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
          minWidth: 80,
        ),
        child: Column(
          crossAxisAlignment: isFromMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.only(
                top: 2,
                bottom: 2,
                left: isFromMe ? 56 : 8,
                right: isFromMe ? 8 : 56,
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(10),
                  topRight: const Radius.circular(10),
                  bottomLeft: Radius.circular(isFromMe ? 10 : 2),
                  bottomRight: Radius.circular(isFromMe ? 2 : 10),
                ),
                border: isCurrentMatch
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : null,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showSenderName && !isFromMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        message.senderDisplayName,
                        style: TextStyle(
                          color: _senderColor(message.senderId.value),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (message.forwarded)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shortcut, size: 14, color: mutedColor),
                          const SizedBox(width: 4),
                          Text(
                            l10n.forwarded,
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (message.hasReply) _ReplyPreview(message: message),
                  _content(context, l10n, mutedColor),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.edited) ...[
                        Text(
                          l10n.edited,
                          style: TextStyle(fontSize: 11, color: mutedColor),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        _formatTime(context, message.sentAt),
                        style: TextStyle(fontSize: 11, color: mutedColor),
                      ),
                      if (isFromMe) ...[
                        const SizedBox(width: 3),
                        _DeliveryIcon(
                          status: message.status,
                          color: mutedColor,
                          l10n: l10n,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isFromMe && message.isFailed)
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 4),
                child: Text(
                  l10n.notSentTapForOptions,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (message.reactions.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  left: isFromMe ? 56 : 12,
                  right: isFromMe ? 12 : 56,
                  bottom: 4,
                ),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final reaction in message.reactions)
                      _ReactionChip(
                        reaction: reaction,
                        onTap: onReactionTap == null
                            ? null
                            : () => onReactionTap!(reaction.key),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AppLocalizations l10n, Color muted) {
    switch (message.kind) {
      case MessageKind.text:
        return _HighlightedBody(text: message.body, query: highlightQuery);
      case MessageKind.image:
        // Unsent images are shown from the copy kept in the outbox.
        return _ImageAttachment(
          load: loadAttachment,
          onTap: onOpenAttachment,
          fallbackLabel: message.attachmentName ?? l10n.photo,
        );
      case MessageKind.voice:
      case MessageKind.audio:
        final load = loadAttachment;
        if (load == null) {
          return _Placeholder(icon: Icons.mic, text: l10n.voiceMessage);
        }
        return VoiceNotePlayer(
          loadBytes: () => load(),
          totalDuration: Duration(
            milliseconds: message.attachmentDurationMs ?? 0,
          ),
          accentColor: Theme.of(context).colorScheme.primary,
          mimeType: message.attachmentMimeType,
        );
      case MessageKind.file:
        final size = message.attachmentSizeBytes;
        return InkWell(
          onTap: message.isPending ? null : onOpenAttachment,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 28),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.attachmentName ?? l10n.file,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    if (size != null)
                      Text(
                        formatBytes(size),
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      case MessageKind.deleted:
      case MessageKind.undecryptable:
      case MessageKind.unsupported:
        return _Placeholder(
          icon: switch (message.kind) {
            MessageKind.deleted => Icons.block,
            MessageKind.undecryptable => Icons.lock_clock_outlined,
            _ => Icons.help_outline,
          },
          text: message.kind == MessageKind.undecryptable
              ? l10n.waitingForKeys
              : messagePreviewText(l10n, message.kind, ''),
        );
    }
  }

  static String _formatTime(BuildContext context, DateTime dt) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.jm(locale).format(dt);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _HighlightedBody extends StatelessWidget {
  const _HighlightedBody({required this.text, this.query});

  final String text;
  final String? query;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 15);
    final q = query?.trim();
    if (q == null || q.isEmpty) {
      return Text(text, style: style);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = q.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + q.length),
          style: const TextStyle(
            backgroundColor: Color(0xFFFFEB3B),
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = index + q.length;
    }

    return Text.rich(TextSpan(children: spans), style: style);
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kind = message.replyToKind;
    final body = message.replyToBody;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 3,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.replyToSenderName ?? l10n.originalMessage,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            kind == null || body == null
                ? l10n.originalMessageUnavailable
                : messagePreviewText(l10n, kind, body),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ImageAttachment extends StatefulWidget {
  const _ImageAttachment({
    required this.load,
    required this.onTap,
    required this.fallbackLabel,
  });

  final AttachmentLoader? load;
  final VoidCallback? onTap;
  final String fallbackLabel;

  @override
  State<_ImageAttachment> createState() => _ImageAttachmentState();
}

class _ImageAttachmentState extends State<_ImageAttachment> {
  Future<Uint8List>? _thumbnail;

  @override
  void initState() {
    super.initState();
    _thumbnail = widget.load?.call(thumbnail: true);
  }

  @override
  Widget build(BuildContext context) {
    final future = _thumbnail;
    if (future == null) {
      return _Placeholder(
        icon: Icons.image_outlined,
        text: widget.fallbackLabel,
      );
    }
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: FutureBuilder<Uint8List>(
          future: future,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null) {
              return Image.memory(
                bytes,
                width: 220,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _Placeholder(
                  icon: Icons.broken_image_outlined,
                  text: widget.fallbackLabel,
                ),
              );
            }
            if (snapshot.hasError) {
              return _Placeholder(
                icon: Icons.broken_image_outlined,
                text: widget.fallbackLabel,
              );
            }
            return const SizedBox(
              width: 220,
              height: 160,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.reaction, this.onTap});

  final Reaction reaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: reaction.includesMe
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: reaction.includesMe
              ? Border.all(color: scheme.primary, width: 1)
              : null,
        ),
        child: Text(
          '${reaction.key} ${reaction.count}',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

/// Matrix has read receipts but no delivery receipts, so there is no
/// "delivered" tick: sending (clock), waiting for the connection (cloud),
/// sent (one tick, only once the server returned the event ID), read (blue
/// ticks), failed (red).
class _DeliveryIcon extends StatelessWidget {
  const _DeliveryIcon({
    required this.status,
    required this.color,
    required this.l10n,
  });

  final MessageDeliveryStatus status;
  final Color color;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageDeliveryStatus.pending:
        return Icon(
          Icons.schedule,
          size: 13,
          color: color,
          semanticLabel: l10n.sending,
        );
      case MessageDeliveryStatus.waitingForNetwork:
        return Icon(
          Icons.cloud_off_outlined,
          size: 13,
          color: color,
          semanticLabel: l10n.waitingForNetwork,
        );
      case MessageDeliveryStatus.sent:
        return Icon(Icons.done, size: 13, color: color);
      case MessageDeliveryStatus.read:
        return const Icon(Icons.done_all, size: 13, color: Color(0xFF4FC3F7));
      case MessageDeliveryStatus.failed:
        return const Icon(Icons.error_outline, size: 13, color: Colors.red);
    }
  }
}
