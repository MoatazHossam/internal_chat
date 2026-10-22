import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../domain/device_trust_state.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/failure_listener.dart';
import '../session/session_controller.dart';
import 'device_trust_controller.dart';

/// Recovery key and device verification. Without one of them a new device
/// cannot read earlier encrypted messages.
class SecurityPage extends GetView<DeviceTrustController> {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final session = Get.find<SessionController>();
    controller.refreshState();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.securityTitle)),
      body: FailureListener(
        failure: controller.failure,
        child: Obx(() {
          final state = controller.state.value;
          final busy = controller.busy.value;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _StatusCard(state: state),
              const SizedBox(height: 24),
              if (busy) const LinearProgressIndicator(),
              if (state == TrustState.needsRecoverySetup)
                FilledButton.icon(
                  icon: const Icon(Icons.key),
                  label: Text(l10n.setUpRecovery),
                  onPressed: busy ? null : () => _setUpRecovery(context, l10n),
                ),
              if (state == TrustState.unverified ||
                  state == TrustState.unverifiedNoRecoveryKey)
                FilledButton.icon(
                  icon: const Icon(Icons.devices),
                  label: Text(l10n.verifyWithOtherDevice),
                  onPressed: busy ? null : controller.verifyWithOtherDevice,
                ),
              if (state == TrustState.unverified) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.key),
                  label: Text(l10n.enterRecoveryKey),
                  onPressed: busy
                      ? null
                      : () => _enterRecoveryKey(context, l10n),
                ),
              ],
              if (state == TrustState.unknown)
                TextButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.retry),
                  onPressed: busy ? null : controller.refreshState,
                ),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l10n.historyLossWarning)),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                l10n.deviceIdValue(session.state.value.user?.deviceId ?? '—'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _setUpRecovery(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final password = await _askForText(
      context,
      title: l10n.confirmPasswordTitle,
      body: l10n.confirmPasswordBody,
      label: l10n.password,
      obscure: true,
      action: l10n.setUpRecovery,
    );
    if (password == null || password.isEmpty) return;
    final key = await controller.setUpRecovery(password);
    if (key == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.recoveryKeyTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.recoveryKeyBody),
            const SizedBox(height: 16),
            SelectableText(
              key.value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: key.value)),
            child: Text(l10n.copy),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.iSavedIt),
          ),
        ],
      ),
    );
  }

  Future<void> _enterRecoveryKey(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final key = await _askForText(
      context,
      title: l10n.enterRecoveryKey,
      body: l10n.enterRecoveryKeyBody,
      label: l10n.recoveryKeyLabel,
      action: l10n.restore,
    );
    if (key == null || key.trim().isEmpty) return;
    final restored = await controller.restoreWithRecoveryKey(key);
    if (restored && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.restoreSuccess)));
    }
  }

  Future<String?> _askForText(
    BuildContext context, {
    required String title,
    required String body,
    required String label,
    required String action,
    bool obscure = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final input = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            const SizedBox(height: 16),
            TextField(
              controller: input,
              autofocus: true,
              obscureText: obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: label),
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final TrustState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, title, body) = switch (state) {
      TrustState.verified => (
        Icons.verified_user,
        Colors.green,
        l10n.trustVerified,
        l10n.trustVerifiedBody,
      ),
      TrustState.unverified => (
        Icons.gpp_maybe_outlined,
        Colors.orange,
        l10n.trustUnverified,
        l10n.trustUnverifiedBody,
      ),
      TrustState.unverifiedNoRecoveryKey => (
        Icons.gpp_maybe_outlined,
        Colors.orange,
        l10n.trustUnverified,
        l10n.trustUnverifiedNoKeyBody,
      ),
      TrustState.needsRecoverySetup => (
        Icons.key_off_outlined,
        Colors.orange,
        l10n.trustNeedsSetup,
        l10n.trustNeedsSetupBody,
      ),
      TrustState.encryptionUnavailable => (
        Icons.gpp_bad_outlined,
        scheme.error,
        l10n.trustUnavailable,
        l10n.errorEncryptionUnavailable,
      ),
      TrustState.unknown => (
        Icons.hourglass_empty,
        scheme.outline,
        l10n.trustUnknown,
        '',
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(body),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
