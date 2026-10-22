import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../app_routes.dart';
import '../../domain/device_trust_state.dart';
import '../../domain/session_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/conversation.dart';
import '../../utilities/message_labels.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/failure_listener.dart';
import '../security/device_trust_controller.dart';
import '../session/session_controller.dart';
import 'chat_controller.dart';
import 'chat_navigation.dart';
import 'new_conversation_dialogs.dart';

class ConversationListPage extends GetView<ChatController> {
  const ConversationListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

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
      body: FailureListener(
        failure: controller.failure,
        child: Column(
          children: [
            const _StatusBanners(),
            Expanded(
              child: Obx(() {
                if (controller.loading.value) {
                  return const Center(child: CircularProgressIndicator());
                }

                final query = searchQuery.value.toLowerCase();
                final items = controller.conversations.where((c) {
                  if (query.isEmpty) return true;
                  return c.title.toLowerCase().contains(query) ||
                      (c.lastMessagePreview?.toLowerCase().contains(query) ??
                          false);
                }).toList();

                if (items.isEmpty) {
                  return _EmptyState(
                    text: query.isEmpty ? l10n.noConversations : l10n.noResults,
                  );
                }

                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: 72,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  itemBuilder: (context, index) {
                    final c = items[index];
                    return c.isInvite
                        ? _InviteTile(conversation: c)
                        : _ConversationTile(conversation: c);
                  },
                );
              }),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showNewConversationSheet(context, controller),
        tooltip: l10n.newConversationTooltip,
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

/// Connection state and a prompt to verify this device.
class _StatusBanners extends StatelessWidget {
  const _StatusBanners();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final session = Get.find<SessionController>();
    final trust = Get.find<DeviceTrustController>();

    return Obx(() {
      final banners = <Widget>[];
      switch (session.state.value.status) {
        case SessionStatus.offline:
          banners.add(_Banner(icon: Icons.cloud_off, text: l10n.offlineBanner));
        case SessionStatus.connecting || SessionStatus.refreshing:
          banners.add(_Banner(icon: Icons.sync, text: l10n.connectingBanner));
        default:
          break;
      }
      final trustText = switch (trust.state.value) {
        TrustState.unverified ||
        TrustState.unverifiedNoRecoveryKey => l10n.verifyDeviceBanner,
        TrustState.needsRecoverySetup => l10n.setUpRecoveryBanner,
        TrustState.encryptionUnavailable => l10n.errorEncryptionUnavailable,
        _ => null,
      };
      if (trustText != null) {
        banners.add(
          _Banner(
            icon: Icons.gpp_maybe_outlined,
            text: trustText,
            onTap: () => Get.toNamed(AppRoutes.security),
          ),
        );
      }
      return Column(mainAxisSize: MainAxisSize.min, children: banners);
    });
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSecondaryContainer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: color.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: color.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final l10n = AppLocalizations.of(context)!;
    final controller = Get.find<ChatController>();
    final invitedBy = c.invitedBy;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AvatarWidget(name: c.title),
      title: Text(
        c.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        invitedBy == null ? l10n.invitation : l10n.invitationFrom(invitedBy),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.decline,
            icon: const Icon(Icons.close),
            onPressed: () => controller.leave(c.id),
          ),
          IconButton.filled(
            tooltip: l10n.accept,
            icon: const Icon(Icons.check),
            onPressed: () => controller.acceptInvite(c.id),
          ),
        ],
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
    final mutedColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    final lastKind = c.lastMessageKind;
    final senderName = c.lastMessageIsOwn ? l10n.you : c.lastMessageSenderName;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AvatarWidget(name: c.title),
      title: Row(
        children: [
          Flexible(
            child: Text(
              c.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!c.isEncrypted) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: l10n.notEncryptedBadge,
              child: Icon(
                Icons.no_encryption_gmailerrorred_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
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
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: mutedColor),
                children: [
                  if (lastKind != null &&
                      senderName != null &&
                      (c.kind == ConversationKind.group ||
                          c.lastMessageIsOwn)) ...[
                    TextSpan(
                      text: '$senderName: ',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                  TextSpan(
                    text: lastKind == null
                        ? ''
                        : messagePreviewText(
                            l10n,
                            lastKind,
                            c.lastMessagePreview ?? '',
                          ),
                  ),
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
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
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
      onTap: () => openConversationPage(controller, c.id),
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
