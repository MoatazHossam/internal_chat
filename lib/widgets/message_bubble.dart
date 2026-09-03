import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/chat_message.dart';
import 'voice_note_player.dart';

/// A WhatsApp-style message bubble.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isFromMe,
    this.showSenderName = false,
    this.highlightQuery,
    this.isCurrentMatch = false,
  });

  final ChatMessage message;
  final bool isFromMe;

  /// Show sender name above the body (used in group chats for incoming msgs).
  final bool showSenderName;

  /// When set, occurrences of this text within [message.body] are
  /// highlighted (used by in-conversation search).
  final String? highlightQuery;

  /// Whether this bubble is the currently focused search match.
  final bool isCurrentMatch;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
        child: Container(
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
                      color: _senderColor(message.senderId),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (message.hasReply) _ReplyPreview(message: message),
              if (message.hasAttachment)
                _AttachmentPreview(message: message)
              else
                _HighlightedBody(
                  text: message.body,
                  query: highlightQuery,
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Spacer(),
                  Text(
                    _formatTime(context, message.sentAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                  if (isFromMe) ...[
                    const SizedBox(width: 3),
                    _DeliveryIcon(status: message.status),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(BuildContext context, DateTime dt) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.jm(locale).format(dt);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            message.replyToSenderName ?? '',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyToBody ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isVoiceNote) {
      final path = message.attachmentLocalPath;
      final duration =
          Duration(milliseconds: message.attachmentDurationMs ?? 0);
      final accent = Theme.of(context).colorScheme.primary;

      if (path == null) {
        // No local playback source available (e.g. arriving from another
        // device in a real backend). Show a disabled placeholder.
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic, size: 18, color: accent),
            const SizedBox(width: 6),
            Text(
              _durationLabel(duration),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        );
      }

      return VoiceNotePlayer(
        source: path,
        totalDuration: duration,
        accentColor: accent,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.attach_file, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            message.attachmentName ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  static String _durationLabel(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _DeliveryIcon extends StatelessWidget {
  const _DeliveryIcon({required this.status});

  final MessageDeliveryStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageDeliveryStatus.pending:
        return const Icon(Icons.schedule, size: 13, color: Colors.black45);
      case MessageDeliveryStatus.sent:
        return const Icon(Icons.done, size: 13, color: Colors.black45);
      case MessageDeliveryStatus.delivered:
        return const Icon(Icons.done_all, size: 13, color: Colors.black45);
      case MessageDeliveryStatus.read:
        return const Icon(Icons.done_all, size: 13, color: Color(0xFF4FC3F7));
      case MessageDeliveryStatus.failed:
        return const Icon(Icons.error_outline, size: 13, color: Colors.red);
    }
  }
}
