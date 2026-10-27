import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show Bidi, DateFormat;

import '../l10n/app_localizations.dart';
import '../models/chat_message.dart';
import '../styles/chat_theme.dart';
import '../styles/tokens.dart';
import '../utilities/failure_messages.dart';
import '../utilities/message_labels.dart';
import 'avatar_widget.dart';
import 'voice_note_player.dart';

typedef AttachmentLoader = Future<Uint8List> Function({bool thumbnail});

/// One message. Consecutive messages from the same person form a group:
/// only the first shows the sender's name, only the last shows their avatar
/// (in group conversations), and the corners where they meet are tighter.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.showSenderName = false,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.highlightQuery,
    this.isCurrentMatch = false,
    this.loadAttachment,
    this.onOpenAttachment,
    this.onReactionTap,
  });

  final ChatMessage message;

  /// Group conversations: name and avatar of other senders.
  final bool showSenderName;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  /// When set, occurrences of this text within [message.body] are
  /// highlighted (used by in-conversation search).
  final String? highlightQuery;

  /// Whether this bubble is the currently focused search match.
  final bool isCurrentMatch;

  final AttachmentLoader? loadAttachment;
  final VoidCallback? onOpenAttachment;
  final void Function(String key)? onReactionTap;

  static const _avatarRadius = 16.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chat = ChatTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final own = message.isOwn;
    final failed = own && message.isFailed;
    final colors = _BubbleColors(
      background: failed
          ? scheme.errorContainer
          : own
          ? chat.outgoing
          : chat.incoming,
      foreground: failed
          ? scheme.onErrorContainer
          : own
          ? chat.onOutgoing
          : chat.onIncoming,
      meta: failed
          ? scheme.onErrorContainer.withValues(alpha: 0.75)
          : own
          ? chat.outgoingMeta
          : chat.incomingMeta,
      accent: own && !failed ? chat.onOutgoing : scheme.primary,
      quote: own && !failed
          ? chat.onOutgoing.withValues(alpha: 0.14)
          : scheme.primary.withValues(alpha: 0.08),
      readReceipt: chat.readReceipt,
      error: scheme.error,
    );
    final showAvatar = showSenderName && !own;
    final isImage = message.kind == MessageKind.image && loadAttachment != null;

    final bubble = Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: _radius(),
        border: isCurrentMatch
            ? Border.all(color: chat.highlight, width: 2)
            : !own
            ? Border.all(color: chat.incomingBorder, width: 0.5)
            : null,
      ),
      padding: isImage
          ? const EdgeInsets.all(Insets.xs)
          : const EdgeInsets.fromLTRB(
              Insets.md,
              Insets.sm,
              Insets.md,
              Insets.sm - 2,
            ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: colors.foreground),
        child: IconTheme.merge(
          data: IconThemeData(color: colors.foreground),
          child: _BubbleContent(
            message: message,
            colors: colors,
            l10n: l10n,
            showSenderName: showSenderName && !own && isFirstInGroup,
            senderColor: chat.identityFor(message.senderId.value),
            highlightQuery: highlightQuery,
            loadAttachment: loadAttachment,
            onOpenAttachment: onOpenAttachment,
            isImage: isImage,
          ),
        ),
      ),
    );
    final direction = Directionality.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: Insets.md,
        right: Insets.md,
        top: isFirstInGroup ? Insets.sm : Insets.xxs,
        bottom: Insets.xxs,
      ),
      child: Row(
        // Own messages on the right, others on the left, in both reading
        // directions.
        textDirection: TextDirection.ltr,
        mainAxisAlignment: own
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showAvatar) ...[
            SizedBox(
              width: _avatarRadius * 2,
              child: isLastInGroup
                  ? AvatarWidget(
                      name: message.senderDisplayName,
                      colorKey: message.senderId.value,
                      radius: _avatarRadius,
                    )
                  : null,
            ),
            const SizedBox(width: Insets.sm),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.76,
              ),
              child: Directionality(
                textDirection: direction,
                child: Column(
                  crossAxisAlignment: own
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    bubble,
                    if (message.reactions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Insets.xs),
                        child: Wrap(
                          spacing: Insets.xs,
                          runSpacing: Insets.xs,
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
                    if (failed)
                      Padding(
                        padding: const EdgeInsets.only(top: Insets.xs),
                        child: Text(
                          l10n.notSentTapForOptions,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.error,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Round corners, except on the sender's side: tighter where this bubble
  /// joins the previous one from the same person, and a small "tail" corner
  /// at the bottom.
  BorderRadius _radius() {
    const round = Radius.circular(Radii.bubble);
    const joined = Radius.circular(Radii.bubbleJoined);
    final senderTop = isFirstInGroup ? round : joined;
    return message.isOwn
        ? BorderRadius.only(
            topLeft: round,
            bottomLeft: round,
            topRight: senderTop,
            bottomRight: joined,
          )
        : BorderRadius.only(
            topRight: round,
            bottomRight: round,
            topLeft: senderTop,
            bottomLeft: joined,
          );
  }
}

class _BubbleColors {
  const _BubbleColors({
    required this.background,
    required this.foreground,
    required this.meta,
    required this.accent,
    required this.quote,
    required this.readReceipt,
    required this.error,
  });

  final Color background;
  final Color foreground;
  final Color meta;
  final Color accent;
  final Color quote;
  final Color readReceipt;
  final Color error;
}

class _BubbleContent extends StatelessWidget {
  const _BubbleContent({
    required this.message,
    required this.colors,
    required this.l10n,
    required this.showSenderName,
    required this.senderColor,
    required this.isImage,
    this.highlightQuery,
    this.loadAttachment,
    this.onOpenAttachment,
  });

  final ChatMessage message;
  final _BubbleColors colors;
  final AppLocalizations l10n;
  final bool showSenderName;
  final Color senderColor;
  final bool isImage;
  final String? highlightQuery;
  final AttachmentLoader? loadAttachment;
  final VoidCallback? onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final header = <Widget>[
      if (showSenderName)
        Padding(
          padding: const EdgeInsets.only(bottom: Insets.xxs),
          child: Text(
            message.senderDisplayName,
            style: TextStyle(
              color: senderColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      if (message.forwarded)
        Padding(
          padding: const EdgeInsets.only(bottom: Insets.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shortcut_rounded, size: 14, color: colors.meta),
              const SizedBox(width: Insets.xs),
              Text(
                l10n.forwarded,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: colors.meta,
                ),
              ),
            ],
          ),
        ),
      if (message.hasReply) _ReplyPreview(message: message, colors: colors),
    ];
    final meta = _Meta(message: message, colors: colors, l10n: l10n);

    if (isImage) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.sm,
                Insets.xs,
                Insets.sm,
                Insets.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: header,
              ),
            ),
          Stack(
            children: [
              _ImageAttachment(
                load: loadAttachment,
                onTap: onOpenAttachment,
                fallbackLabel: message.attachmentName ?? l10n.photo,
              ),
              PositionedDirectional(
                end: Insets.sm,
                bottom: Insets.sm,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.sm,
                    vertical: Insets.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: _Meta(
                    message: message,
                    colors: colors,
                    l10n: l10n,
                    overrideColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (message.kind == MessageKind.text) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...header,
          // Short messages keep the time on the same line; longer ones
          // move it under the text, at the end.
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: Insets.sm,
            children: [
              _HighlightedBody(text: message.body, query: highlightQuery),
              Padding(
                padding: const EdgeInsets.only(top: Insets.xs),
                child: meta,
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [...header, _body()],
        ),
        const SizedBox(height: Insets.xs),
        meta,
      ],
    );
  }

  Widget _body() {
    switch (message.kind) {
      case MessageKind.text:
      case MessageKind.image:
        return _Placeholder(
          icon: Icons.image_outlined,
          text: message.attachmentName ?? l10n.photo,
          color: colors.meta,
        );
      case MessageKind.voice:
      case MessageKind.audio:
        final load = loadAttachment;
        if (load == null) {
          return _Placeholder(
            icon: Icons.mic_none_rounded,
            text: l10n.voiceMessage,
            color: colors.meta,
          );
        }
        return VoiceNotePlayer(
          loadBytes: () => load(),
          totalDuration: Duration(
            milliseconds: message.attachmentDurationMs ?? 0,
          ),
          accentColor: colors.accent,
          onAccentColor: colors.background,
          mimeType: message.attachmentMimeType,
        );
      case MessageKind.file:
        final size = message.attachmentSizeBytes;
        return InkWell(
          onTap: message.isPending ? null : onOpenAttachment,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.xxs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.quote,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    size: 22,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(width: Insets.md),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.attachmentName ?? l10n.file,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (size != null)
                        Text(
                          formatBytes(size),
                          style: TextStyle(fontSize: 12, color: colors.meta),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      case MessageKind.deleted:
      case MessageKind.undecryptable:
      case MessageKind.unsupported:
        return _Placeholder(
          icon: switch (message.kind) {
            MessageKind.deleted => Icons.block_rounded,
            MessageKind.undecryptable => Icons.lock_clock_outlined,
            _ => Icons.help_outline_rounded,
          },
          text: message.kind == MessageKind.undecryptable
              ? l10n.waitingForKeys
              : messagePreviewText(l10n, message.kind, ''),
          color: colors.meta,
        );
    }
  }
}

/// "edited", the time and, for own messages, the delivery state.
class _Meta extends StatelessWidget {
  const _Meta({
    required this.message,
    required this.colors,
    required this.l10n,
    this.overrideColor,
  });

  final ChatMessage message;
  final _BubbleColors colors;
  final AppLocalizations l10n;
  final Color? overrideColor;

  @override
  Widget build(BuildContext context) {
    final color = overrideColor ?? colors.meta;
    final style = TextStyle(fontSize: 11.5, color: color, height: 1.2);
    final locale = Localizations.localeOf(context).toString();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.edited) ...[
          Text(l10n.edited, style: style),
          const SizedBox(width: Insets.xs),
        ],
        Text(DateFormat.jm(locale).format(message.sentAt), style: style),
        if (message.isOwn) ...[
          const SizedBox(width: Insets.xs),
          _DeliveryIcon(
            status: message.status,
            color: color,
            readColor: overrideColor ?? colors.readReceipt,
            errorColor: colors.error,
            l10n: l10n,
          ),
        ],
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: Insets.xs + 2),
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
    const style = TextStyle(fontSize: 16, height: 1.3);
    // English in an Arabic interface (and the reverse) reads in its own
    // direction, so punctuation stays where the writer put it.
    final direction = Bidi.detectRtlDirectionality(text)
        ? TextDirection.rtl
        : TextDirection.ltr;
    final q = query?.trim();
    if (q == null || q.isEmpty) {
      return Text(text, style: style, textDirection: direction);
    }

    final chat = ChatTheme.of(context);
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
          style: TextStyle(
            backgroundColor: chat.highlight,
            color: chat.onHighlight,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = index + q.length;
    }

    return Text.rich(
      TextSpan(children: spans),
      style: style,
      textDirection: direction,
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.message, required this.colors});

  final ChatMessage message;
  final _BubbleColors colors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final kind = message.replyToKind;
    final body = message.replyToBody;

    return Container(
      margin: const EdgeInsets.only(bottom: Insets.xs + 2),
      decoration: BoxDecoration(
        color: colors.quote,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: colors.accent),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.sm,
                  Insets.xs + 1,
                  Insets.sm + 2,
                  Insets.xs + 1,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.replyToSenderName ?? l10n.originalMessage,
                      style: TextStyle(
                        color: colors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      kind == null || body == null
                          ? l10n.originalMessageUnavailable
                          : messagePreviewText(l10n, kind, body),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: colors.foreground.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
  static const _width = 240.0;
  Future<Uint8List>? _thumbnail;

  @override
  void initState() {
    super.initState();
    _thumbnail = widget.load?.call(thumbnail: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget frame(Widget child) => Container(
      width: _width,
      height: 180,
      color: scheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: child,
    );
    final fallback = frame(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(height: Insets.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.md),
            child: Text(
              widget.fallbackLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.bubble - Insets.xs),
        child: FutureBuilder<Uint8List>(
          future: _thumbnail,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null) {
              return Image.memory(
                bytes,
                width: _width,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                // Keeps the bubble's size while the image decodes.
                frameBuilder: (context, child, frameNumber, synchronous) =>
                    frameNumber == null && !synchronous
                    ? frame(const SizedBox.shrink())
                    : child,
                errorBuilder: (_, _, _) => fallback,
              );
            }
            if (snapshot.hasError || _thumbnail == null) return fallback;
            return frame(
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
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
    final mine = reaction.includesMe;
    return Material(
      color: mine ? scheme.primaryContainer : scheme.surface,
      shape: StadiumBorder(
        side: BorderSide(color: mine ? scheme.primary : scheme.outlineVariant),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.sm,
            vertical: Insets.xxs + 1,
          ),
          child: Text(
            '${reaction.key} ${reaction.count}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: mine ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Matrix has read receipts but no delivery receipts, so there is no
/// "delivered" tick: sending (clock), waiting for the connection (cloud),
/// sent (one tick, only once the server returned the event ID), read (two
/// ticks, highlighted), failed (error).
class _DeliveryIcon extends StatelessWidget {
  const _DeliveryIcon({
    required this.status,
    required this.color,
    required this.readColor,
    required this.errorColor,
    required this.l10n,
  });

  final MessageDeliveryStatus status;
  final Color color;
  final Color readColor;
  final Color errorColor;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    const size = 15.0;
    return switch (status) {
      MessageDeliveryStatus.pending => Icon(
        Icons.schedule_rounded,
        size: size,
        color: color,
        semanticLabel: l10n.sending,
      ),
      MessageDeliveryStatus.waitingForNetwork => Icon(
        Icons.cloud_off_rounded,
        size: size,
        color: color,
        semanticLabel: l10n.waitingForNetwork,
      ),
      MessageDeliveryStatus.sent => Icon(
        Icons.done_rounded,
        size: size,
        color: color,
      ),
      MessageDeliveryStatus.read => Icon(
        Icons.done_all_rounded,
        size: size,
        color: readColor,
      ),
      MessageDeliveryStatus.failed => Icon(
        Icons.error_rounded,
        size: size,
        color: errorColor,
      ),
    };
  }
}
