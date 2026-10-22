import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../domain/session_state.dart';
import '../../l10n/app_localizations.dart';
import '../../utilities/failure_messages.dart';
import '../session/session_controller.dart';
import 'authentication_controller.dart';

class LoginPage extends GetView<AuthenticationController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final idController = TextEditingController();
    final passwordController = TextEditingController();
    final obscure = true.obs;
    final session = Get.find<SessionController>();
    final mutedColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.forum_rounded,
                      size: 80,
                      color: Color(0xFF075E54),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.appTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.loginSubtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: mutedColor),
                    ),
                    Obx(() {
                      final expired =
                          session.state.value.signOutReason ==
                          SignOutReason.sessionExpired;
                      if (!expired) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _Notice(
                          icon: Icons.lock_clock_outlined,
                          text: l10n.errorSessionExpired,
                        ),
                      );
                    }),
                    const SizedBox(height: 40),

                    TextField(
                      controller: idController,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.username],
                      decoration: InputDecoration(
                        labelText: l10n.username,
                        hintText: l10n.usernameHint,
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Obx(
                      () => TextField(
                        controller: passwordController,
                        obscureText: obscure.value,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: l10n.password,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscure.value
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () => obscure.value = !obscure.value,
                          ),
                        ),
                        onSubmitted: (_) =>
                            _signIn(idController, passwordController),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Obx(() {
                      final failure = controller.failure.value;
                      if (failure == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          failureMessage(l10n, failure),
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
                            : () => _signIn(idController, passwordController),
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
                              : Text(l10n.signIn),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Text(
                      l10n.loginFooter,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn(
    TextEditingController id,
    TextEditingController password,
  ) async {
    final success = await controller.signIn(id.text, password.text);
    // Never keep the password around after an attempt.
    if (success) password.clear();
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
