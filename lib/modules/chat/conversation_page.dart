import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../app_routes.dart';
import '../../domain/chat_backend.dart';
import '../../domain/chat_failure.dart';
import '../../domain/ids.dart';
import '../../l10n/app_localizations.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../utilities/message_labels.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/failure_listener.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/typing_indicator.dart';
import 'chat_controller.dart';

const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

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

  ConversationId get _conversationId {
    final open = controller.currentConversationId.value;
    if (open != null) return open;
    // Opened from a route without going through the list. Opening changes
    // observable state, so it must not happen during build.
    final id = ConversationId(Uri.decodeComponent(Get.parameters['id'] ?? ''));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => controller.openConversation(id),
    );
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final conversationId = _conversationId;

    _searchWorkerBox.worker ??= ever<String?>(
      controller.currentMatchMessageId,
      (id) {
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
      },
    );

    return PopScope(
      onPopInvokedWithResult: (_, _) {
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
            final conversation = controller.currentConversation;
            final title = conversation?.title ?? '';
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        _AppBarSubtitle(
                          controller: controller,
                          conversation: conversation,
                          l10n: l10n,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () =>
                      _showConversationMenu(context, l10n, conversationId),
                ),
              ],
            );
          }),
        ),
        body: FailureListener(
          failure: controller.failure,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0D1418)
                      : const Color(0xFFECE5DD),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      final metrics = notification.metrics;
                      if (metrics.pixels >= metrics.maxScrollExtent - 300) {
                        controller.loadOlder();
                      }
                      return false;
                    },
                    child: Obx(() {
                      final msgs = controller.messages;
                      final isGroup =
                          controller.currentConversation?.kind ==
                          ConversationKind.group;

                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        itemCount: msgs.length + 1,
                        itemBuilder: (context, index) {
                          // Typing and history loading at the top (the end of
                          // the reversed list).
                          if (index == msgs.length) {
                            return _ListHeader(controller: controller);
                          }

                          final msg = msgs[index];
                          final key = _messageKeys.putIfAbsent(
                            msg.id,
                            () => GlobalKey(),
                          );
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
                                onTap: msg.isFailed
                                    ? () => _showMessageOptions(
                                        context,
                                        l10n,
                                        msg,
                                      )
                                    : null,
                                child: Obx(
                                  () => MessageBubble(
                                    message: msg,
                                    showSenderName: isGroup,
                                    highlightQuery:
                                        controller.messageSearchQuery.value,
                                    isCurrentMatch:
                                        controller
                                            .currentMatchMessageId
                                            .value ==
                                        msg.id,
                                    loadAttachment:
                                        ({bool thumbnail = false}) =>
                                            controller.attachmentBytes(
                                              msg,
                                              thumbnail: thumbnail,
                                            ),
                                    onOpenAttachment: () =>
                                        _openAttachment(context, l10n, msg),
                                    onReactionTap: (reaction) => controller
                                        .toggleReaction(msg, reaction),
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
              ),

              // Reply or edit bar
              Obx(() {
                final editing = controller.editing.value;
                if (editing != null) {
                  return _ComposerContextBar(
                    title: l10n.editingMessage,
                    body: editing.body,
                    icon: Icons.edit,
                    onDismiss: () {
                      controller.cancelEditing();
                      _input.clear();
                      _hasText.value = false;
                    },
                  );
                }
                final reply = controller.replyTo.value;
                if (reply == null) return const SizedBox.shrink();
                return _ComposerContextBar(
                  title: reply.senderDisplayName,
                  body: messagePreviewText(
                    l10n,
                    reply.kind,
                    reply.body,
                    attachmentName: reply.attachmentName,
                  ),
                  onDismiss: () => controller.setReplyTo(null),
                );
              }),

              // Input bar, or why sending is disabled.
              Obx(() {
                final conversation = controller.currentConversation;
                if (conversation != null && !conversation.isEncrypted) {
                  return _SendingDisabledBar(text: l10n.notEncryptedComposer);
                }
                return _InputBar(
                  conversationId: conversationId,
                  inputController: _input,
                  hasText: _hasText,
                  controller: controller,
                  l10n: l10n,
                );
              }),
            ],
          ),
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
    final isSent = !message.isPending && !message.isFailed;
    final canInteract =
        isSent &&
        message.kind != MessageKind.deleted &&
        message.kind != MessageKind.undecryptable;

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canInteract)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final reaction in _quickReactions)
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          controller.toggleReaction(message, reaction);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            reaction,
                            style: const TextStyle(fontSize: 26),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (message.isFailed)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(l10n.retry),
                onTap: () {
                  Navigator.pop(sheetContext);
                  controller.retry(message);
                },
              ),
            if (canInteract)
              ListTile(
                leading: const Icon(Icons.reply),
                title: Text(l10n.reply),
                onTap: () {
                  Navigator.pop(sheetContext);
                  controller.setReplyTo(message);
                },
              ),
            if (message.kind == MessageKind.text)
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(l10n.copyText),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Clipboard.setData(ClipboardData(text: message.body));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.copiedToClipboard)),
                  );
                },
              ),
            if (message.canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.edit),
                onTap: () {
                  Navigator.pop(sheetContext);
                  controller.startEditing(message);
                  _input.text = message.body;
                  _hasText.value = message.body.trim().isNotEmpty;
                },
              ),
            if (message.canDelete)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  l10n.delete,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDelete(context, l10n, message);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppLocalizations l10n,
    ChatMessage message,
  ) async {
    // Unsent messages are simply discarded; nothing reached the server.
    if (message.isFailed || message.isPending) {
      await controller.delete(message);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.delete(message);
  }

  Future<void> _openAttachment(
    BuildContext context,
    AppLocalizations l10n,
    ChatMessage message,
  ) async {
    if (message.kind == MessageKind.image) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: FutureBuilder<Uint8List>(
                  future: controller.attachmentBytes(message),
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes == null) {
                      return snapshot.hasError
                          ? const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54,
                              size: 48,
                            )
                          : const CircularProgressIndicator();
                    }
                    return InteractiveViewer(child: Image.memory(bytes));
                  },
                ),
              ),
              SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    // Other files: decrypt into memory and let the user choose where to save
    // the copy. Saved copies are outside the app's control.
    try {
      final bytes = await controller.attachmentBytes(message);
      final path = await FilePicker.platform.saveFile(
        fileName: message.attachmentName ?? 'file',
        bytes: bytes,
      );
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.fileSaved)));
      }
    } on ChatFailure catch (failure) {
      controller.failure
        ..value = failure
        ..refresh();
    } catch (_) {
      controller.failure
        ..value = const UnexpectedFailure()
        ..refresh();
    }
  }

  void _showConversationMenu(
    BuildContext context,
    AppLocalizations l10n,
    ConversationId conversationId,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.conversationInfo),
              onTap: () {
                Navigator.pop(sheetContext);
                Get.toNamed(
                  AppRoutes.conversationInfo,
                  arguments: conversationId,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: Text(l10n.searchInConversation),
              onTap: () {
                Navigator.pop(sheetContext);
                controller.openMessageSearch();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.logout,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.leaveConversation,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmLeave(context, l10n, conversationId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLeave(
    BuildContext context,
    AppLocalizations l10n,
    ConversationId conversationId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.leaveConversation),
        content: Text(l10n.leaveConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.leaveConversation),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.leave(conversationId);
    if (context.mounted) Navigator.of(context).maybePop();
  }
}

// ---------------------------------------------------------------------------
// App bar subtitle
// ---------------------------------------------------------------------------

class _AppBarSubtitle extends StatelessWidget {
  const _AppBarSubtitle({
    required this.controller,
    required this.conversation,
    required this.l10n,
  });

  final ChatController controller;
  final Conversation? conversation;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final typing = controller.typingLabel.value;
      if (typing != null) {
        return Text(
          l10n.isTypingSuffix(typing),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: Colors.white70,
          ),
        );
      }
      final current = conversation;
      if (current == null) return const SizedBox.shrink();
      final encrypted = current.isEncrypted;
      return Row(
        children: [
          Icon(
            encrypted ? Icons.lock_outline : Icons.no_encryption_outlined,
            size: 12,
            color: encrypted ? Colors.white70 : Colors.orangeAccent,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              encrypted ? l10n.encryptedSubtitle : l10n.notEncryptedBadge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: encrypted ? Colors.white70 : Colors.orangeAccent,
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final children = <Widget>[
        if (controller.loadingOlder.value)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (controller.typingLabel.value != null)
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TypingIndicator(),
            ),
          ),
      ];
      if (children.isEmpty) return const SizedBox.shrink();
      return Column(mainAxisSize: MainAxisSize.min, children: children);
    });
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

class _SendingDisabledBar extends StatelessWidget {
  const _SendingDisabledBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        color: scheme.errorContainer,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.no_encryption_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.conversationId,
    required this.inputController,
    required this.hasText,
    required this.controller,
    required this.l10n,
  });

  final ConversationId conversationId;
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

    // The recording is read into memory and its plaintext file deleted
    // right away; the backend encrypts the bytes before upload.
    Uint8List? bytes;
    try {
      final file = File(path);
      // Shorter than a second is an accidental tap; discard it, matching
      // common chat-app behaviour.
      if (duration >= const Duration(seconds: 1)) {
        bytes = await file.readAsBytes();
      }
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Best-effort cleanup; nothing to recover from here.
    }
    if (bytes == null) return;

    await widget.controller.sendVoiceNote(
      conversationId: widget.conversationId,
      file: FileSource(
        name: 'voice-message.m4a',
        bytes: bytes,
        mimeType: 'audio/mp4',
      ),
      duration: duration,
    );
  }

  Future<void> _pickAttachment() async {
    final l10n = widget.l10n;
    final type = await showModalBottomSheet<FileType>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: Text(l10n.photo),
              onTap: () => Navigator.pop(sheetContext, FileType.image),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(l10n.document),
              onTap: () => Navigator.pop(sheetContext, FileType.any),
            ),
          ],
        ),
      ),
    );
    if (type == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: type,
      withData: kIsWeb,
    );
    final picked = result?.files.singleOrNull;
    if (picked == null) return;

    // Check the server's limit before reading the whole file into memory.
    final max = await widget.controller.maxUploadBytes();
    if (max != null && picked.size > max) {
      widget.controller.failure
        ..value = TooLarge(maxBytes: max)
        ..refresh();
      await _clearPickerCopies();
      return;
    }

    Uint8List? bytes = picked.bytes;
    final path = picked.path;
    if (bytes == null && path != null) bytes = await File(path).readAsBytes();
    await _clearPickerCopies();
    if (bytes == null) return;

    await widget.controller.sendFile(
      widget.conversationId,
      FileSource(name: picked.name, bytes: bytes, mimeType: _mimeType(picked)),
    );
  }

  /// The picker copies files into the app's cache; remove those plaintext
  /// copies once the bytes are in memory.
  Future<void> _clearPickerCopies() async {
    if (kIsWeb) return;
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {
      // Not supported on every platform.
    }
  }

  static String? _mimeType(PlatformFile file) =>
      switch (file.extension?.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'pdf' => 'application/pdf',
        _ => null,
      };

  void _send() {
    final text = widget.inputController.text;
    widget.inputController.clear();
    widget.hasText.value = false;
    // Not awaited: the message shows as "sending" immediately and may take
    // a while to go out when offline.
    widget.controller.send(widget.conversationId, text);
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
                              onChanged: (v) {
                                widget.hasText.value = v.trim().isNotEmpty;
                                widget.controller.onComposerChanged(
                                  widget.conversationId,
                                  v,
                                );
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.attach_file),
                            color: Colors.grey,
                            onPressed: _pickAttachment,
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
                      onPressed: _send,
                      child: Icon(
                        widget.controller.editing.value == null
                            ? Icons.send
                            : Icons.check,
                      ),
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
                        // Recording needs press-and-hold; a tap explains it.
                        onPressed: () => ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(content: Text(widget.l10n.holdToRecord)),
                          ),
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
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
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
// Reply / edit bar
// ---------------------------------------------------------------------------

class _ComposerContextBar extends StatelessWidget {
  const _ComposerContextBar({
    required this.title,
    required this.body,
    required this.onDismiss,
    this.icon,
  });

  final String title;
  final String body;
  final IconData? icon;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1F2C34)
          : const Color(0xFFF0F2F5),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Container(width: 3, height: 40, color: primary),
          const SizedBox(width: 10),
          if (icon != null) ...[
            Icon(icon, size: 18, color: primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: onDismiss),
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
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ),
      ),
    );
  }

  static String _label(
    BuildContext context,
    DateTime dt,
    AppLocalizations l10n,
  ) {
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
