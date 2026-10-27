import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../domain/chat_failure.dart';
import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../utilities/failure_messages.dart';
import '../../widgets/app_logo.dart';
import 'session_controller.dart';

/// Shown while the encrypted store opens and a saved session is restored. If
/// either fails, the app stops here rather than continuing unprotected.
class SplashPage extends GetView<SessionController> {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Obx(() {
              final failure = controller.startupFailure.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(),
                  const SizedBox(height: Insets.xxl),
                  if (failure == null) ...[
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(height: Insets.lg),
                    Text(
                      l10n.startingUp,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else ...[
                    Icon(
                      Icons.gpp_bad_outlined,
                      size: 40,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: Insets.md),
                    Text(
                      failureMessage(l10n, failure),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Insets.lg),
                    FilledButton(
                      onPressed: controller.resetting.value
                          ? null
                          : controller.restore,
                      child: Text(l10n.retry),
                    ),
                    // Deleting local data is never automatic: only offered
                    // when the store exists but cannot be opened.
                    if (failure is LocalDataUnreadable) ...[
                      const SizedBox(height: Insets.sm),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: controller.resetting.value
                            ? null
                            : () => _confirmReset(context, l10n),
                        child: Text(l10n.resetLocalData),
                      ),
                    ],
                  ],
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReset(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.resetLocalDataConfirmTitle),
        content: Text(l10n.resetLocalDataConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.resetLocalData),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.resetLocalData();
  }
}
