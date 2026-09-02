import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../../../app/theme/app_theme.dart';

class LoginView extends GetView<AuthController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final emailCtrl    = TextEditingController();
    final passwordCtrl = TextEditingController();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // UAE flag stripe accent
                Container(
                  height: 6,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [AppTheme.uaeRed, AppTheme.uaeGreen]),
                    borderRadius: BorderRadius.all(Radius.circular(3)),
                  ),
                ),
                const SizedBox(height: 32),
                const Icon(Icons.chat_bubble_outline, size: 64, color: AppTheme.uaeGreen),
                const SizedBox(height: 16),
                Text(
                  'داخلي',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.uaeGreen,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Internal Chat',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to your account',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outlined),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _doLogin(emailCtrl, passwordCtrl),
                ),
                const SizedBox(height: 8),
                Obx(() {
                  if (controller.error.value == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      controller.error.value!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  );
                }),
                const SizedBox(height: 24),
                Obx(() => FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.uaeGreen),
                  onPressed: controller.isLoading.value
                      ? null
                      : () => _doLogin(emailCtrl, passwordCtrl),
                  child: controller.isLoading.value
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('تسجيل الدخول  ·  Sign In'),
                )),
                const SizedBox(height: 16),
                Text(
                  'Demo: moataz@company.ae · omar@company.ae · seif@company.ae\nأي كلمة مرور',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _doLogin(TextEditingController email, TextEditingController password) {
    controller.login(email.text.trim(), password.text);
  }
}
