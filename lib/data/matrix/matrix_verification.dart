import 'dart:async';

import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../../domain/chat_failure.dart';
import '../../domain/device_trust_state.dart';
import 'matrix_errors.dart';

/// Drives one SDK [KeyVerification] through the emoji (SAS) flow and
/// reports it as domain [VerificationStep]s. QR verification is not offered.
final class MatrixVerificationRequest implements VerificationRequest {
  MatrixVerificationRequest(this._verification, {void Function()? onDone})
    : _onDone = onDone {
    _verification.onUpdate = _handleUpdate;
    _handleUpdate();
  }

  final KeyVerification _verification;
  final void Function()? _onDone;
  final _steps = StreamController<VerificationStep>.broadcast();
  VerificationStep _step = const VerificationWaiting();
  bool _choseSas = false;

  @override
  bool get isSelfVerification =>
      _verification.userId == _verification.client.userID;

  @override
  String get otherUserId => _verification.userId;

  @override
  String? get otherDeviceId => _verification.deviceId;

  @override
  VerificationStep get step => _step;

  @override
  Stream<VerificationStep> get steps => _steps.stream;

  @override
  Future<void> accept() => _guard(_verification.acceptVerification);

  @override
  Future<void> confirmEmojisMatch() => _guard(_verification.acceptSas);

  @override
  Future<void> rejectEmojis() => _guard(_verification.rejectSas);

  @override
  Future<void> cancel() async {
    if (_verification.isDone) return;
    await _guard(() => _verification.cancel('m.user'));
  }

  void _handleUpdate() {
    final next = switch (_verification.state) {
      KeyVerificationState.askAccept => const VerificationIncoming(),
      KeyVerificationState.askSas => VerificationCompareEmojis([
        for (final emoji in _verification.sasEmojis)
          SasEmoji(emoji.emoji, emoji.name),
      ]),
      KeyVerificationState.done => const VerificationDone(),
      KeyVerificationState.error => VerificationCancelled(
        byOtherSide: _verification.canceledCode != 'm.user',
      ),
      _ => const VerificationWaiting(),
    };

    switch (_verification.state) {
      case KeyVerificationState.askChoice:
        // Both sides are ready; continue with emoji comparison. The SDK
        // resolves the race if the other side starts at the same time.
        if (!_choseSas &&
            _verification.possibleMethods.contains(EventTypes.Sas)) {
          _choseSas = true;
          _background(() => _verification.continueVerification(EventTypes.Sas));
        }
      case KeyVerificationState.askSSSS:
        // The SDK offers to unlock secret storage to sign the other device.
        // Recovery is handled on the security page, so skip it here.
        _background(() => _verification.openSSSS(skip: true));
      case KeyVerificationState.showQRSuccess ||
          KeyVerificationState.confirmQRScan:
        _background(cancel);
      default:
        break;
    }

    if (next.runtimeType == _step.runtimeType &&
        next is! VerificationCompareEmojis) {
      return;
    }
    _step = next;
    if (!_steps.isClosed) _steps.add(next);
    if (next is VerificationDone || next is VerificationCancelled) {
      if (next is VerificationDone) _onDone?.call();
      _verification.onUpdate = null;
      unawaited(_steps.close());
    }
  }

  /// Runs an SDK step the user did not trigger. A failure there ends the
  /// verification, which the SDK reports as a cancelled state.
  void _background(Future<void> Function() action) {
    unawaited(action().catchError((Object _) {}));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      final failure = toChatFailure(error);
      throw failure is UnexpectedFailure ? const NotAvailable() : failure;
    }
  }
}
