import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app_routes.dart';
import 'authentication_controller.dart';

class LoginPage extends GetView<AuthenticationController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final idController = TextEditingController();
    final passwordController = TextEditingController();
    final obscure = true.obs;

    return Scaffold(
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
                  // Logo
                  const Icon(
                    Icons.forum_rounded,
                    size: 80,
                    color: Color(0xFF075E54),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Internal Chat',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in with your organizational account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                  const SizedBox(height: 40),

                  // Email / username
                  TextField(
                    controller: idController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email or username',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password
                  Obx(
                    () => TextField(
                      controller: passwordController,
                      obscureText: obscure.value,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Password',
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
                      onSubmitted: (_) => _signIn(
                        context,
                        idController,
                        passwordController,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Error message
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

                  // Sign-in button
                  Obx(
                    () => FilledButton(
                      onPressed: controller.loading.value
                          ? null
                          : () => _signIn(
                                context,
                                idController,
                                passwordController,
                              ),
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
                            : const Text('Sign in'),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'Access is restricted to authorized personnel.\nContact IT support if you cannot sign in.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.45),
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

  Future<void> _signIn(
    BuildContext context,
    TextEditingController id,
    TextEditingController password,
  ) async {
    final success = await controller.signIn(id.text, password.text);
    if (!context.mounted) return;

    if (success) {
      Get.offAllNamed(AppRoutes.conversations);
    } else if (controller.mfaChallenge.value != null) {
      Get.toNamed(AppRoutes.mfa);
    }
  }
}
