import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/avatar_widget.dart';
import 'settings_controller.dart';

extension _RetentionOptionLabel on RetentionOption {
  String label(AppLocalizations l10n) {
    switch (this) {
      case RetentionOption.sessionOnly:
        return l10n.retentionSessionOnly;
      case RetentionOption.oneDay:
        return l10n.retentionOneDay;
      case RetentionOption.sevenDays:
        return l10n.retentionSevenDays;
      case RetentionOption.thirtyDays:
        return l10n.retentionThirtyDays;
      case RetentionOption.ninetyDays:
        return l10n.retentionNinetyDays;
      case RetentionOption.oneEightyDays:
        return l10n.retentionSixMonths;
      case RetentionOption.oneYear:
        return l10n.retentionOneYear;
    }
  }
}

class SettingsPage extends GetView<SettingsController> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: Obx(
        () => ListView(
          children: [
            // Profile header
            _ProfileHeader(controller: controller, l10n: l10n),

            const Divider(height: 1),

            // Account section
            _SectionHeader(label: l10n.account),
            Obx(
              () => ListTile(
                leading: const Icon(Icons.email_outlined),
                title: Text(l10n.email),
                subtitle: Text(
                  controller.currentUser.value?.email ?? '—',
                ),
              ),
            ),

            const Divider(height: 1),

            // Privacy section
            _SectionHeader(label: l10n.privacyStorage),
            Obx(
              () => ListTile(
                leading: const Icon(Icons.history),
                title: Text(l10n.deviceHistoryRetention),
                subtitle: Text(controller.selectedRetention.value.label(l10n)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showRetentionPicker(context, l10n),
              ),
            ),

            const Divider(height: 1),

            // Appearance section
            _SectionHeader(label: l10n.appearance),
            Obx(
              () => SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
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
                leading: const Icon(Icons.language_outlined),
                title: Text(l10n.language),
                subtitle: Text(
                  controller.locale.value.languageCode == 'ar'
                      ? l10n.languageArabic
                      : l10n.languageEnglish,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showLanguagePicker(context, l10n),
              ),
            ),

            const Divider(height: 1),

            // Danger zone
            _SectionHeader(label: l10n.session),
            ListTile(
              leading: Icon(
                Icons.logout,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.signOut,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => _confirmSignOut(context, l10n),
            ),

            const SizedBox(height: 32),
            Center(
              child: Text(
                l10n.prototypeFooter,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.4),
                    ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showRetentionPicker(BuildContext context, AppLocalizations l10n) {
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
                l10n.retentionSheetTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                l10n.retentionSheetBody,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
              ),
            ),
            ...controller.availableRetentionOptions.map(
              (option) => Obx(
                () => ListTile(
                  title: Text(option.label(l10n)),
                  trailing: controller.selectedRetention.value == option
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    controller.setRetention(option);
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ],
        ),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                l10n.languageSubtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.controller, required this.l10n});

  final SettingsController controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Row(
        children: [
          Obx(
            () => AvatarWidget(
              name: controller.currentUser.value?.displayName ?? 'U',
              radius: 36,
              isOnline: true,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Obx(
              () => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.currentUser.value?.displayName ?? '—',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    controller.currentUser.value?.email ?? '',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l10n.online,
                      style: const TextStyle(
                        color: Color(0xFF4CAF50),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
