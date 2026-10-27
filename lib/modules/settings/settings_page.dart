import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app_routes.dart';
import '../../l10n/app_localizations.dart';
import '../../styles/status_colors.dart';
import '../../styles/tokens.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/section_card.dart';
import '../push/push_controller.dart';
import 'settings_controller.dart';

class SettingsPage extends GetView<SettingsController> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final scheme = Theme.of(context).colorScheme;
    final status = StatusColors.of(context);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainerLow,
        title: Text(l10n.settingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          Insets.sm,
          Insets.lg,
          Insets.xxl,
        ),
        children: [
          _ProfileHeader(controller: controller),
          const SizedBox(height: Insets.xl),
          SectionCard(
            title: l10n.account,
            children: [
              Obx(
                () => ListTile(
                  leading: const TileIcon(Icons.alternate_email_rounded),
                  title: Text(l10n.userId),
                  subtitle: Text(controller.currentUser.value?.id.value ?? '—'),
                ),
              ),
              Obx(
                () => ListTile(
                  leading: const TileIcon(Icons.smartphone_rounded),
                  title: Text(l10n.deviceId),
                  subtitle: Text(controller.currentUser.value?.deviceId ?? '—'),
                ),
              ),
              ListTile(
                leading: TileIcon(
                  Icons.verified_user_outlined,
                  color: status.success,
                ),
                title: Text(l10n.securityTitle),
                subtitle: Text(l10n.securitySubtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Get.toNamed(AppRoutes.security),
              ),
            ],
          ),
          const SizedBox(height: Insets.xl),
          SectionCard(
            title: l10n.privacyStorage,
            children: [
              // Not enforced yet, so nothing to choose: says what happens
              // now.
              ListTile(
                leading: const TileIcon(Icons.history_rounded),
                title: Text(l10n.deviceHistoryRetention),
                subtitle: Text(l10n.retentionNotAvailable),
              ),
            ],
          ),
          const SizedBox(height: Insets.xl),
          if (Get.isRegistered<PushController>()) ...[
            SectionCard(
              children: [_NotificationsTile(push: Get.find<PushController>())],
            ),
            const SizedBox(height: Insets.xl),
          ],
          SectionCard(
            title: l10n.appearance,
            children: [
              Obx(
                () => SwitchListTile(
                  secondary: const TileIcon(Icons.dark_mode_outlined),
                  title: Text(l10n.darkMode),
                  subtitle: Text(l10n.darkModeSubtitle),
                  value: controller.isDarkMode.value,
                  onChanged: (value) {
                    controller.isDarkMode.value = value;
                    Get.changeThemeMode(
                      value ? ThemeMode.dark : ThemeMode.light,
                    );
                  },
                ),
              ),
              Obx(
                () => ListTile(
                  leading: const TileIcon(Icons.translate_rounded),
                  title: Text(l10n.language),
                  subtitle: Text(
                    controller.locale.value.languageCode == 'ar'
                        ? l10n.languageArabic
                        : l10n.languageEnglish,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showLanguagePicker(context, l10n),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.xl),
          SectionCard(
            children: [
              ListTile(
                leading: TileIcon(Icons.logout_rounded, color: scheme.error),
                title: Text(
                  l10n.signOut,
                  style: TextStyle(color: scheme.error),
                ),
                onTap: () => _confirmSignOut(context, l10n),
              ),
            ],
          ),
          const SizedBox(height: Insets.xl),
          Text(
            l10n.prototypeFooter,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                l10n.language,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                l10n.languageSubtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            for (final locale in const [Locale('en'), Locale('ar')])
              Obx(
                () => ListTile(
                  title: Text(
                    locale.languageCode == 'ar'
                        ? l10n.languageArabic
                        : l10n.languageEnglish,
                  ),
                  trailing: controller.locale.value == locale
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    controller.setLocale(locale);
                    Navigator.pop(context);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context, AppLocalizations l10n) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.signOutConfirmTitle),
        content: Text(l10n.signOutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(context);
              controller.signOut();
            },
            child: Text(l10n.signOut),
          ),
        ],
      ),
    );
  }
}

/// Whether push notifications work on this device, and the way to fix it
/// when they do not.
class _NotificationsTile extends StatelessWidget {
  const _NotificationsTile({required this.push});

  final PushController push;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final status = push.status.value;
      final (text, color, onTap) = switch (status) {
        PushStatus.on => (l10n.notificationsOn, null, null),
        PushStatus.notConfigured => (
          l10n.notificationsNotConfigured,
          scheme.onSurfaceVariant,
          null,
        ),
        PushStatus.pending => (l10n.notificationsPending, null, null),
        PushStatus.denied => (
          l10n.notificationsDenied,
          scheme.error,
          openAppSettings,
        ),
        PushStatus.unavailable => (
          l10n.notificationsUnavailable,
          scheme.error,
          () => push.updateRegistration(force: true),
        ),
      };
      return ListTile(
        leading: TileIcon(
          status == PushStatus.on
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          color: color,
        ),
        title: Text(l10n.notifications),
        subtitle: Text(text),
        trailing: onTap == null
            ? null
            : const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
    });
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Obx(() {
          final user = controller.currentUser.value;
          return Row(
            children: [
              AvatarWidget(
                name: user?.displayName ?? '?',
                colorKey: user?.id.value,
                radius: 30,
              ),
              const SizedBox(width: Insets.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: Insets.xxs),
                    Text(
                      user?.id.value ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
