import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../app_routes.dart';
import '../../l10n/app_localizations.dart';
import '../../models/conversation.dart';
import '../../widgets/avatar_widget.dart';
import 'chat_controller.dart';

class ConversationListPage extends GetView<ChatController> {
  const ConversationListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    controller.loadConversations();

    final searchActive = false.obs;
    final searchQuery = ''.obs;
    final searchController = TextEditingController();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Obx(
          () => AppBar(
            title: searchActive.value
                ? TextField(
                    controller: searchController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: l10n.searchHint,
                      hintStyle: const TextStyle(color: Colors.white60),
                      border: InputBorder.none,
                      fillColor: Colors.transparent,
                    ),
                    onChanged: (v) => searchQuery.value = v,
                  )
                : Text(l10n.appTitle),
            actions: [
              if (searchActive.value)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    searchActive.value = false;
                    searchQuery.value = '';
                    searchController.clear();
                  },
                )
              else ...[
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: l10n.searchTooltip,
                  onPressed: () => searchActive.value = true,
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: l10n.settingsTooltip,
                  onPressed: () => Get.toNamed(AppRoutes.settings),
                ),
              ],
            ],
          ),
        ),
      ),
      body: Obx(() {
        if (controller.loading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final query = searchQuery.value.toLowerCase();
        final items = controller.conversations.where((c) {
          if (query.isEmpty) return true;
          return c.title.toLowerCase().contains(query) ||
              (c.lastMessagePreview?.toLowerCase().contains(query) ?? false);
        }).toList();

        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  query.isEmpty ? l10n.noConversations : l10n.noResults,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: controller.loadConversations,
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 72,
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.5),
            ),
            itemBuilder: (context, index) {
              final c = items[index];
              return _ConversationTile(conversation: c);
            },
          ),
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // New conversation — placeholder until backend contacts API exists.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.newConversationRequiresApi),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        tooltip: l10n.newConversationTooltip,
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final l10n = AppLocalizations.of(context)!;
    final controller = Get.find<ChatController>();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AvatarWidget(
        name: c.title,
        isOnline: c.isOnline,
      ),
      title: Text(
        c.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: c.isTyping
          ? Text(
              l10n.typingLabel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontStyle: FontStyle.italic,
              ),
            )
          : RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                children: [
                  if (c.lastMessageSenderName != null &&
                      c.kind == ConversationKind.group) ...[
                    TextSpan(
                      text: '${c.lastMessageSenderName}: ',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                  TextSpan(text: c.lastMessagePreview ?? ''),
                ],
              ),
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (c.lastActivityAt != null)
            Text(
              _formatTimestamp(context, c.lastActivityAt!, l10n),
              style: TextStyle(
                fontSize: 12,
                color: c.unreadCount > 0
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
              ),
            ),
          const SizedBox(height: 4),
          if (c.unreadCount > 0)
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                c.unreadCount > 99 ? '99+' : '${c.unreadCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            const SizedBox(height: 20),
        ],
      ),
      onTap: () {
        controller.openConversation(c.id);
        Get.toNamed(
          AppRoutes.conversation.replaceFirst(':id', c.id),
          parameters: {
            'title': c.title,
            'kind': c.kind.name,
          },
        );
      },
    );
  }

  static String _formatTimestamp(
    BuildContext context,
    DateTime dt,
    AppLocalizations l10n,
  ) {
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;

    if (diff == 0) {
      return DateFormat.jm(locale).format(dt);
    } else if (diff == 1) {
      return l10n.yesterday;
    } else if (diff < 7) {
      return DateFormat.E(locale).format(dt);
    } else {
      return DateFormat.yMd(locale).format(dt);
    }
  }
}
