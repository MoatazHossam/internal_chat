import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../services/contracts.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/typing_indicator.dart';
import 'chat_controller.dart';

class ConversationPage extends GetView<ChatController> {
  ConversationPage({super.key});

  final _input = TextEditingController();
  final _scrollController = ScrollController();
  final _hasText = false.obs;

  @override
  Widget build(BuildContext context) {
    final conversationId = Get.parameters['id'] ?? '';
    final title = Get.parameters['title'] ?? 'Chat';
    final isGroup = Get.parameters['kind'] == ConversationKind.group.name;

    // Wire up realtime typing events from the realtime service.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final realtimeService = Get.find<RealtimeService>();
      controller.listenToRealtime(realtimeService.events);
    });

    return PopScope(
      onPopInvokedWithResult: (_, __) => controller.closeConversation(),
      child: Scaffold(
        appBar: AppBar(
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
                          '$typing is typing…',
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
                      return const Text(
                        'tap for info',
                        style: TextStyle(
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
              onPressed: () => _showConversationMenu(context, conversationId),
            ),
          ],
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
                          return Padding(
                            padding: const EdgeInsets.only(
                              left: 12,
                              bottom: 4,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: const TypingIndicator(),
                            ),
                          );
                        });
                      }

                      final msg = msgs[index];
                      final isFromMe = msg.senderId == 'current-user';

                      // Date separator between messages on different days.
                      final showDateSeparator = _shouldShowDateSeparator(
                        msgs,
                        index,
                      );

                      return Column(
                        children: [
                          if (showDateSeparator)
                            _DateSeparator(date: msg.sentAt),
                          GestureDetector(
                            onLongPress: () =>
                                _showMessageOptions(context, msg),
                            child: MessageBubble(
                              message: msg,
                              isFromMe: isFromMe,
                              showSenderName: isGroup,
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
              );
            }),

            // Input bar
            _InputBar(
              conversationId: conversationId,
              inputController: _input,
              hasText: _hasText,
              controller: controller,
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

  void _showMessageOptions(BuildContext context, ChatMessage message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                controller.setReplyTo(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy text'),
              onTap: () {
                Navigator.pop(context);
                // Clipboard interaction would go here.
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showConversationMenu(BuildContext context, String conversationId) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Conversation info'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search in conversation'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.conversationId,
    required this.inputController,
    required this.hasText,
    required this.controller,
  });

  final String conversationId;
  final TextEditingController inputController;
  final RxBool hasText;
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1F2C34)
            : const Color(0xFFF0F2F5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF2A3942)
                      : Colors.white,
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
                        controller: inputController,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                          fillColor: Colors.transparent,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (v) => hasText.value = v.trim().isNotEmpty,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.attach_file),
                      color: Colors.grey,
                      onPressed: () {
                        // File attachment requires backend contracts.
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Attachments require the file upload API.',
                            ),
                            duration: Duration(seconds: 2),
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
              () => FloatingActionButton.small(
                elevation: 0,
                onPressed: () {
                  if (hasText.value) {
                    final text = inputController.text;
                    inputController.clear();
                    hasText.value = false;
                    controller.send(conversationId, text);
                  }
                },
                child: Icon(
                  hasText.value ? Icons.send : Icons.mic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reply bar
// ---------------------------------------------------------------------------

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.message, required this.onDismiss});

  final ChatMessage message;
  final VoidCallback onDismiss;

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
                  message.body,
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
  const _DateSeparator({required this.date});

  final DateTime date;

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
            _label(date),
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

  static String _label(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
