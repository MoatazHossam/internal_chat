import 'dart:async';

import 'package:get/get.dart';

import '../../app_routes.dart';
import '../../domain/chat_backend.dart';
import '../../domain/chat_failure.dart';
import '../../domain/session_state.dart';

/// App-wide: restores the saved session at startup and moves between the
/// login and conversation screens when the session changes (sign in, sign
/// out, or the server ending the session).
class SessionController extends GetxController {
  SessionController(this._session);

  final ChatSession _session;

  final state = Rx<SessionState>(const SessionState.initializing());

  /// Set when the local encrypted store or encryption could not start. The
  /// app stays on the start screen instead of continuing without them.
  final startupFailure = Rxn<ChatFailure>();

  StreamSubscription<SessionState>? _subscription;
  bool _started = false;

  @override
  void onInit() {
    super.onInit();
    _subscription = _session.sessionState.listen(_onState);
  }

  @override
  void onReady() {
    super.onReady();
    restore();
  }

  Future<void> restore() async {
    startupFailure.value = null;
    try {
      await _session.restore();
      _started = true;
      _route(state.value);
    } on ChatFailure catch (failure) {
      startupFailure.value = failure;
    }
  }

  void _onState(SessionState next) {
    final previous = state.value;
    state.value = next;
    if (!_started) return;
    if (next.isSignedIn != previous.isSignedIn ||
        next.status == SessionStatus.signedOut &&
            previous.status != SessionStatus.signedOut) {
      _route(next);
    }
  }

  void _route(SessionState current) {
    if (current.isSignedIn) {
      if (Get.currentRoute != AppRoutes.conversations) {
        Get.offAllNamed(AppRoutes.conversations);
      }
    } else if (current.status == SessionStatus.signedOut) {
      if (Get.currentRoute != AppRoutes.login) {
        Get.offAllNamed(AppRoutes.login);
      }
    }
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
