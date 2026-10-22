import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../domain/chat_failure.dart';
import '../l10n/app_localizations.dart';
import '../utilities/failure_messages.dart';

/// Shows a snack bar each time [failure] is reported.
class FailureListener extends StatefulWidget {
  const FailureListener({
    super.key,
    required this.failure,
    required this.child,
  });

  final Rxn<ChatFailure> failure;
  final Widget child;

  @override
  State<FailureListener> createState() => _FailureListenerState();
}

class _FailureListenerState extends State<FailureListener> {
  late final Worker _worker;

  @override
  void initState() {
    super.initState();
    _worker = ever<ChatFailure?>(widget.failure, (failure) {
      if (failure == null || !mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failureMessage(l10n, failure))));
    });
  }

  @override
  void dispose() {
    _worker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
