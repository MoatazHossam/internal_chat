import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';

class MfaView extends GetView<AuthController> {
  const MfaView({super.key});

  @override
  Widget build(BuildContext context) {
    final codeCtrl = TextEditingController();
    return Scaffold(
      appBar: AppBar(title: const Text('Two-Factor Authentication')),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const Icon(Icons.security, size: 48),
            const SizedBox(height: 16),
            const Text('Enter your MFA code'),
            const SizedBox(height: 24),
            TextField(
              controller: codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: '6-digit code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => controller.login('', ''),
              child: const Text('Verify'),
            ),
          ],
        ),
      ),
    );
  }
}
