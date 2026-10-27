import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
                    const SizedBox(height: 12),
                    Text(
                      failureMessage(l10n, failure),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: controller.restore,
                      child: Text(l10n.retry),
                    ),
                  ],
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
