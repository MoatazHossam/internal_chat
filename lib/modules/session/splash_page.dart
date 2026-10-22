import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../l10n/app_localizations.dart';
import '../../utilities/failure_messages.dart';
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
                  const Icon(
                    Icons.forum_rounded,
                    size: 72,
                    color: Color(0xFF075E54),
                  ),
                  const SizedBox(height: 24),
                  if (failure == null) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(l10n.startingUp),
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
