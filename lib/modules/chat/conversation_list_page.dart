import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../app_routes.dart';
import '../../domain/device_trust_state.dart';
import '../../domain/ids.dart';
import '../../domain/session_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/conversation.dart';
import '../../styles/tokens.dart';
import '../../utilities/message_labels.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/failure_listener.dart';
import '../push/push_controller.dart';
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

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(
          l10n.appTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTooltip,
            onPressed: () => Get.toNamed(AppRoutes.settings),
          ),
          const SizedBox(width: Insets.xs),
        ],
      ),
      body: FailureListener(
        failure: controller.failure,
        child: _NotificationOpener(
          controller: controller,
          child: _ConversationListBody(controller: controller),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showNewConversationSheet(context, controller),
        tooltip: l10n.newConversationTooltip,
        icon: const Icon(Icons.add_comment_outlined),
        label: Text(l10n.newConversationTooltip),
      ),
    );
  }
}

class _ConversationListBody extends StatefulWidget {
  const _ConversationListBody({required this.controller});

  final ChatController controller;

  @override
  State<_ConversationListBody> createState() => _ConversationListBodyState();
}

class _ConversationListBodyState extends State<_ConversationListBody> {
  final _search = TextEditingController();
  final _query = ''.obs;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = widget.controller;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.xs,
            Insets.lg,
            Insets.sm,
          ),
          child: Obx(
            () => TextField(
              controller: _search,
              onChanged: (value) => _query.value = value,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                suffixIcon: _query.value.isEmpty
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).deleteButtonTooltip,
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _search.clear();
                          _query.value = '';
                        },
                      ),
              ),
            ),
          ),
        ),
        const _StatusBanners(),
        Expanded(
          child: Obx(() {
            if (controller.loading.value) {
              return const Center(child: CircularProgressIndicator());
            }

            final query = _query.value.trim().toLowerCase();
            final items = controller.conversations.where((c) {
              if (query.isEmpty) return true;
              return c.title.toLowerCase().contains(query) ||
                  (c.lastMessagePreview?.toLowerCase().contains(query) ??
                      false);
            }).toList();

            if (items.isEmpty) {
              return _EmptyState(
                icon: query.isEmpty
                    ? Icons.forum_outlined
                    : Icons.search_off_rounded,
                text: query.isEmpty ? l10n.noConversations : l10n.noResults,
              );
            }

            return ListView.builder(
              // Room for the floating button below the last row.
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: items.length,
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
    );
  }
}

/// Opens the conversation of a tapped notification. The list is the root
/// page while signed in, so it is always there to do this.
class _NotificationOpener extends StatefulWidget {
  const _NotificationOpener({required this.controller, required this.child});

  final ChatController controller;
  final Widget child;

  @override
  State<_NotificationOpener> createState() => _NotificationOpenerState();
}

class _NotificationOpenerState extends State<_NotificationOpener> {
  Worker? _worker;

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<PushController>()) return;
    final push = Get.find<PushController>();
    _worker = ever<String?>(push.openRequest, _open);
    // A tap that started the app arrived before this page existed.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _open(push.openRequest.value),
    );
  }

  void _open(String? roomId) {
    if (roomId == null || !mounted) return;
    Get.find<PushController>().openRequest.value = null;
    // Back to the list first: only one conversation is open at a time.
    Get.until((route) => route.settings.name == AppRoutes.conversations);
    openConversationPage(widget.controller, ConversationId(roomId));
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
          banners.add(
            _Banner(icon: Icons.cloud_off_outlined, text: l10n.offlineBanner),
          );
        case SessionStatus.connecting || SessionStatus.refreshing:
          banners.add(
            _Banner(icon: Icons.sync_rounded, text: l10n.connectingBanner),
          );
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
            icon: Icons.shield_outlined,
            text: trustText,
            prominent: true,
            onTap: () => Get.toNamed(AppRoutes.security),
          ),
        );
      }
      return Column(mainAxisSize: MainAxisSize.min, children: banners);
    });
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.onTap,
    this.prominent = false,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  /// Asks the user to act (accent colours) rather than just informing.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = prominent
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    final foreground = prominent
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.sm),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.md),
          child: Padding(
            padding: const EdgeInsets.all(Insets.md),
            child: Row(
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: foreground),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: foreground,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: Insets.lg),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The shared layout of a list row: avatar, a title line and a detail line.
class _Row extends StatelessWidget {
  const _Row({
    required this.conversation,
    required this.title,
    required this.detail,
    this.trailingTop,
    this.trailingBottom,
    this.onTap,
  });

  final Conversation conversation;
  final Widget title;
  final Widget detail;
  final Widget? trailingTop;
  final Widget? trailingBottom;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md - 2,
        ),
        child: Row(
          children: [
            AvatarWidget(
              name: conversation.title,
              colorKey: conversation.id.value,
              isGroup: conversation.kind == ConversationKind.group,
              radius: 26,
            ),
            const SizedBox(width: Insets.md + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: title),
                      if (trailingTop != null) ...[
                        const SizedBox(width: Insets.sm),
                        trailingTop!,
                      ],
                    ],
                  ),
                  const SizedBox(height: Insets.xs),
                  Row(
                    children: [
                      Expanded(child: detail),
                      if (trailingBottom != null) ...[
                        const SizedBox(width: Insets.sm),
                        trailingBottom!,
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
    final theme = Theme.of(context);
    final controller = Get.find<ChatController>();
    final invitedBy = c.invitedBy;

    return _Row(
      conversation: c,
      title: Text(
        c.title,
        style: theme.textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      detail: Text(
        invitedBy == null ? l10n.invitation : l10n.invitationFrom(invitedBy),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailingTop: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.outlined(
            tooltip: l10n.decline,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => controller.leave(c.id),
          ),
          const SizedBox(width: Insets.xs),
          IconButton.filled(
            tooltip: l10n.accept,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.check_rounded, size: 20),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = Get.find<ChatController>();
    final unread = c.unreadCount > 0;
    final lastKind = c.lastMessageKind;
    final senderName = c.lastMessageIsOwn ? l10n.you : c.lastMessageSenderName;
    final detailStyle = theme.textTheme.bodyMedium?.copyWith(
      color: unread ? scheme.onSurface : scheme.onSurfaceVariant,
    );

    return _Row(
      conversation: c,
      onTap: () => openConversationPage(controller, c.id),
      title: Row(
        children: [
          Flexible(
            child: Text(
              c.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!c.isEncrypted) ...[
            const SizedBox(width: Insets.xs + 2),
            Tooltip(
              message: l10n.notEncryptedBadge,
              child: Icon(
                Icons.no_encryption_gmailerrorred_outlined,
                size: 16,
                color: scheme.error,
              ),
            ),
          ],
        ],
      ),
      trailingTop: c.lastActivityAt == null
          ? null
          : Text(
              _formatTimestamp(context, c.lastActivityAt!, l10n),
              style: theme.textTheme.bodySmall?.copyWith(
                color: unread ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
      detail: c.isTyping
          ? Text(
              l10n.typingLabel,
              maxLines: 1,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w500,
              ),
            )
          : Text.rich(
              TextSpan(
                children: [
                  if (lastKind != null &&
                      senderName != null &&
                      (c.kind == ConversationKind.group || c.lastMessageIsOwn))
                    TextSpan(
                      text: '$senderName: ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: detailStyle,
            ),
      trailingBottom: unread ? _UnreadBadge(count: c.unreadCount) : null,
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

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: scheme.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
