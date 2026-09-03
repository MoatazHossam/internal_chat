import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../services/contracts.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/typing_indicator.dart';
import 'chat_controller.dart';

/// Holds the search-scroll worker in a mutable box so [ConversationPage]
/// (a `StatelessWidget`) can lazily create and dispose it without violating
/// the `@immutable` contract on its own fields.
class _WorkerBox {
  Worker? worker;
}

class ConversationPage extends GetView<ChatController> {
  ConversationPage({super.key});

  final _input = TextEditingController();
  final _scrollController = ScrollController();
  final _hasText = false.obs;
  final Map<String, GlobalKey> _messageKeys = {};
  final _searchWorkerBox = _WorkerBox();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final conversationId = Get.parameters['id'] ?? '';
    final title = Get.parameters['title'] ?? 'Chat';
    final isGroup = Get.parameters['kind'] == ConversationKind.group.name;

    // Wire up realtime typing events from the realtime service.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final realtimeService = Get.find<RealtimeService>();
      controller.listenToRealtime(realtimeService.events);
    });

    _searchWorkerBox.worker ??=
        ever<String?>(controller.currentMatchMessageId, (
      id,
    ) {
      if (id == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final matchContext = _messageKeys[id]?.currentContext;
        if (matchContext != null) {
          Scrollable.ensureVisible(
            matchContext,
            duration: const Duration(milliseconds: 250),
            alignment: 0.5,
          );
        }
      });
    });

    return PopScope(
      onPopInvokedWithResult: (_, __) {
        _searchWorkerBox.worker?.dispose();
        _searchWorkerBox.worker = null;
        controller.closeConversation();
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Obx(() {
            if (controller.messageSearchActive.value) {
              return _SearchAppBar(controller: controller, l10n: l10n);
            }
            return AppBar(
              titleSpacing: 0,
              title: Row(
                children: [
                  AvatarWidget(name: title, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Obx(() {
                          final typing = controller.typingLabel.value;
                          if (typing != null) {
                            return Text(
                              l10n.isTypingSuffix(typing),
                              style: const TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: Colors.white70,
                              ),
                            );
                          }
                          if (isGroup) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            l10n.tapForInfo,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () =>
                      _showConversationMenu(context, l10n, controller),
                ),
              ],
            );
          }),
        ),
        body: Column(
          children: [
            Expanded(
              child: Container(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF0D1418)
                    : const Color(0xFFECE5DD),
                child: Obx(() {
                  final msgs = controller.messages;

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    itemCount: msgs.length + 1,
                    itemBuilder: (context, index) {
                      // Show typing indicator at top (bottom of reversed list).
                      if (index == msgs.length) {
                        return Obx(() {
                          if (controller.typingLabel.value == null) {
                            return const SizedBox.shrink();
                          }
                          return const Padding(
                            padding: EdgeInsets.only(left: 12, bottom: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TypingIndicator(),
                            ),
                          );
                        });
                      }

                      final msg = msgs[index];
                      final isFromMe = msg.senderId == 'current-user';
                      final key = _messageKeys.putIfAbsent(
                        msg.id,
                        () => GlobalKey(),
                      );

                      // Date separator between messages on different days.
                      final showDateSeparator = _shouldShowDateSeparator(
                        msgs,
                        index,
                      );

                      return Column(
                        key: key,
                        children: [
                          if (showDateSeparator)
                            _DateSeparator(date: msg.sentAt, l10n: l10n),
                          GestureDetector(
                            onLongPress: () =>
                                _showMessageOptions(context, l10n, msg),
                            child: Obx(
                              () => MessageBubble(
                                message: msg,
                                isFromMe: isFromMe,
                                showSenderName: isGroup,
                                highlightQuery:
                                    controller.messageSearchQuery.value,
                                isCurrentMatch:
                                    controller.currentMatchMessageId.value ==
                                        msg.id,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                }),
              ),
            ),

            // Reply bar
            Obx(() {
              final reply = controller.replyTo.value;
              if (reply == null) return const SizedBox.shrink();
              return _ReplyBar(
                message: reply,
                onDismiss: () => controller.setReplyTo(null),
                l10n: l10n,
              );
            }),

            // Input bar
            _InputBar(
              conversationId: conversationId,
              inputController: _input,
              hasText: _hasText,
              controller: controller,
              l10n: l10n,
            ),
          ],
        ),
      ),
    );
  }

  bool _shouldShowDateSeparator(List<ChatMessage> msgs, int index) {
    if (index == msgs.length - 1) return true;
    final current = msgs[index].sentAt;
    final next = msgs[index + 1].sentAt;
    return !_sameDay(current, next);
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _showMessageOptions(
    BuildContext context,
    AppLocalizations l10n,
    ChatMessage message,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: Text(l10n.reply),
              onTap: () {
                Navigator.pop(context);
                controller.setReplyTo(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(l10n.copyText),
              onTap: () async {
                Navigator.pop(context);
                await Clipboard.setData(ClipboardData(text: message.body));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.copiedToClipboard)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showConversationMenu(
    BuildContext context,
    AppLocalizations l10n,
    ChatController controller,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.conversationInfo),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: Text(l10n.searchInConversation),
              onTap: () {
                Navigator.pop(context);
                controller.openMessageSearch();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search app bar
// ---------------------------------------------------------------------------

class _SearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SearchAppBar({required this.controller, required this.l10n});

  final ChatController controller;
  final AppLocalizations l10n;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: controller.closeMessageSearch,
      ),
      title: TextField(
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          hintText: l10n.searchMessagesHint,
          hintStyle: const TextStyle(color: Colors.white60),
          border: InputBorder.none,
        ),
        onChanged: controller.updateMessageSearch,
      ),
      actions: [
        Obx(() {
          final total = controller.messageSearchMatchIds.length;
          if (total > 0) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.matchCounter(controller.currentMatchPosition, total),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: controller.goToOlderMatch,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: controller.goToNewerMatch,
                ),
              ],
            );
          }
          if (controller.messageSearchQuery.value.isNotEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  l10n.noMatches,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------

class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.conversationId,
    required this.inputController,
    required this.hasText,
    required this.controller,
    required this.l10n,
  });

  final String conversationId;
  final TextEditingController inputController;
  final RxBool hasText;
  final ChatController controller;
  final AppLocalizations l10n;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isCancelling = false;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;
  String? _recordingPath;

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.l10n.microphonePermissionDenied)),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(const RecordConfig(), path: path);

    setState(() {
      _isRecording = true;
      _isCancelling = false;
      _elapsed = Duration.zero;
      _recordingPath = path;
    });

    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _finishRecording({required bool cancel}) async {
    _elapsedTimer?.cancel();
    final duration = _elapsed;
    final path = _recordingPath;

    setState(() {
      _isRecording = false;
      _isCancelling = false;
      _elapsed = Duration.zero;
      _recordingPath = null;
    });

    if (cancel || path == null) {
      await _recorder.cancel();
      return;
    }

    await _recorder.stop();

    if (duration < const Duration(seconds: 1)) {
      // Too short to be a meaningful voice note; discard silently, matching
      // common chat-app behavior for accidental taps.
      try {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      } catch (_) {
        // Best-effort cleanup; nothing to recover from here.
      }
      return;
    }

    await widget.controller.sendVoiceNote(
      conversationId: widget.conversationId,
      localPath: path,
      duration: duration,
    );
  }

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Container(
        color: isDark ? const Color(0xFF1F2C34) : const Color(0xFFF0F2F5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _isRecording
                  ? _RecordingIndicator(
                      elapsedLabel: _formatElapsed(_elapsed),
                      isCancelling: _isCancelling,
                      l10n: widget.l10n,
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A3942) : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.emoji_emotions_outlined),
                            color: Colors.grey,
                            onPressed: () {},
                          ),
                          Expanded(
                            child: TextField(
                              controller: widget.inputController,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                hintText: widget.l10n.messageHint,
                                border: InputBorder.none,
                                fillColor: Colors.transparent,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              onChanged: (v) =>
                                  widget.hasText.value = v.trim().isNotEmpty,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.attach_file),
                            color: Colors.grey,
                            onPressed: () {
                              // File attachment requires backend contracts.
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text(widget.l10n.attachmentsRequireApi),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            Obx(
              () => widget.hasText.value
                  ? FloatingActionButton.small(
                      elevation: 0,
                      onPressed: () {
                        final text = widget.inputController.text;
                        widget.inputController.clear();
                        widget.hasText.value = false;
                        widget.controller.send(widget.conversationId, text);
                      },
                      child: const Icon(Icons.send),
                    )
                  : GestureDetector(
                      onLongPressStart: (_) => _startRecording(),
                      onLongPressMoveUpdate: (details) {
                        if (!_isRecording) return;
                        final cancelling = details.offsetFromOrigin.dx < -80;
                        if (cancelling != _isCancelling) {
                          setState(() => _isCancelling = cancelling);
                        }
                      },
                      onLongPressEnd: (_) {
                        if (!_isRecording) return;
                        _finishRecording(cancel: _isCancelling);
                      },
                      onLongPressCancel: () {
                        if (!_isRecording) return;
                        _finishRecording(cancel: true);
                      },
                      child: FloatingActionButton.small(
                        elevation: 0,
                        onPressed: () {},
                        backgroundColor: _isRecording
                            ? Theme.of(context).colorScheme.error
                            : null,
                        child: const Icon(Icons.mic),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator({
    required this.elapsedLabel,
    required this.isCancelling,
    required this.l10n,
  });

  final String elapsedLabel;
  final bool isCancelling;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
          const SizedBox(width: 8),
          Text(elapsedLabel, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              l10n.slideToCancelRecording,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                color: isCancelling
                    ? Theme.of(context).colorScheme.error
                    : Colors.grey,
                fontWeight: isCancelling ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const Icon(Icons.chevron_left, color: Colors.grey, size: 18),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reply bar
// ---------------------------------------------------------------------------

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.message,
    required this.onDismiss,
    required this.l10n,
  });

  final ChatMessage message;
  final VoidCallback onDismiss;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1F2C34)
          : const Color(0xFFF0F2F5),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.senderDisplayName,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  message.isVoiceNote ? l10n.voiceMessage : message.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date separator
// ---------------------------------------------------------------------------

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date, required this.l10n});

  final DateTime date;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1F2C34).withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            _label(context, date, l10n),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.65),
            ),
          ),
        ),
      ),
    );
  }

  static String _label(
      BuildContext context, DateTime dt, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;

    if (diff == 0) return l10n.today;
    if (diff == 1) return l10n.yesterday;

    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMd(locale).format(dt);
  }
}
