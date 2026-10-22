import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/chat_failure.dart';
import '../../domain/device_trust_state.dart';
import '../../l10n/app_localizations.dart';
import '../../utilities/failure_messages.dart';

/// Emoji (SAS) verification with another device or user.
class VerificationDialog extends StatefulWidget {
  const VerificationDialog({super.key, required this.request});

  final VerificationRequest request;

  @override
  State<VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<VerificationDialog> {
  late VerificationStep _step = widget.request.step;
  StreamSubscription<VerificationStep>? _subscription;
  ChatFailure? _failure;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.request.steps.listen((step) {
      if (mounted) setState(() => _step = step);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    final step = _step;
    if (step is! VerificationDone && step is! VerificationCancelled) {
      widget.request.cancel().then<void>((_) {}, onError: (Object _) {});
    }
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _working = true;
      _failure = null;
    });
    try {
      await action();
    } on ChatFailure catch (error) {
      if (mounted) setState(() => _failure = error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final request = widget.request;
    final step = _step;

    final (Widget content, List<Widget> actions) = switch (step) {
      VerificationIncoming() => (
        Text(
          request.isSelfVerification
              ? l10n.verificationIncomingSelf
              : l10n.verificationIncomingUser(request.otherUserId),
        ),
        [
          TextButton(
            onPressed: _working
                ? null
                : () => _act(request.cancel).whenComplete(_close),
            child: Text(l10n.decline),
          ),
          FilledButton(
            onPressed: _working ? null : () => _act(request.accept),
            child: Text(l10n.accept),
          ),
        ],
      ),
      VerificationWaiting() => (
        Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(l10n.verificationWaiting)),
          ],
        ),
        [TextButton(onPressed: _close, child: Text(l10n.cancel))],
      ),
      VerificationCompareEmojis(:final emojis) => (
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.verificationCompare),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final emoji in emojis)
                  SizedBox(
                    width: 64,
                    child: Column(
                      children: [
                        Text(emoji.emoji, style: const TextStyle(fontSize: 32)),
                        const SizedBox(height: 4),
                        Text(
                          emoji.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        [
          TextButton(
            onPressed: _working ? null : () => _act(request.rejectEmojis),
            child: Text(l10n.theyDontMatch),
          ),
          FilledButton(
            onPressed: _working ? null : () => _act(request.confirmEmojisMatch),
            child: Text(l10n.theyMatch),
          ),
        ],
      ),
      VerificationDone() => (
        Row(
          children: [
            const Icon(Icons.verified_user, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.verificationDone)),
          ],
        ),
        [FilledButton(onPressed: _close, child: Text(l10n.close))],
      ),
      VerificationCancelled() => (
        Text(l10n.verificationCancelled),
        [TextButton(onPressed: _close, child: Text(l10n.close))],
      ),
    };

    final failure = _failure;
    return AlertDialog(
      title: Text(l10n.verificationTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          if (failure != null) ...[
            const SizedBox(height: 12),
            Text(
              failureMessage(l10n, failure),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: actions,
    );
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }
}
