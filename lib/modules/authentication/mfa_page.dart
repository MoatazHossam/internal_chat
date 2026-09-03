import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../app_routes.dart';
import '../../l10n/app_localizations.dart';
import 'authentication_controller.dart';

class MfaPage extends GetView<AuthenticationController> {
  const MfaPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final codeController = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.verifySignIn)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 64,
                    color: Color(0xFF075E54),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.twoStepVerification,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.mfaSubtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: Theme.of(context).textTheme.headlineMedium,
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: '• • • • • •',
                    ),
                    onSubmitted: (_) => _verify(context, codeController),
                  ),
                  const SizedBox(height: 12),
                  Obx(() {
                    final msg = controller.error.value;
                    if (msg == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        msg,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }),
                  Obx(
                    () => FilledButton(
                      onPressed: controller.loading.value
                          ? null
                          : () => _verify(context, codeController),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: controller.loading.value
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(l10n.verify),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Get.back(),
                    child: Text(l10n.backToSignIn),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.mfaDemoHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.35),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _verify(
    BuildContext context,
    TextEditingController code,
  ) async {
    final success = await controller.verifyMfa(code.text);
    if (!context.mounted) return;

    if (success) {
      Get.offAllNamed(AppRoutes.conversations);
    }
  }
}
