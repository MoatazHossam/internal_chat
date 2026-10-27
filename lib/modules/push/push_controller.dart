import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../domain/chat_backend.dart';
import '../../domain/chat_failure.dart';
import '../../domain/push.dart';
import '../../domain/session_state.dart';
import '../../l10n/app_localizations.dart';
import '../../services/locale_service.dart';
import '../../services/push_platform.dart';

enum PushStatus {
  /// This build has no push gateway configured.
  notConfigured,

  /// Not signed in yet, or registering.
  pending,

  /// The user did not allow notifications.
  denied,

  /// No push token (for example Firebase is not configured) or the server
  /// refused the registration.
  unavailable,

  /// Registered with the homeserver.
  on,
}

/// App-wide: registers this device for push notifications after sign-in
/// and whenever the token or the language changes, clears delivered
/// notifications when the app comes to the front, and turns notification
/// taps into [openRequest]s.
class PushController extends GetxController with WidgetsBindingObserver {
  PushController(
    this._platform,
    this._registration,
    this._session, {
    required this.enabled,
    Locale Function()? locale,
  }) : _locale = locale ?? LocaleService.current;

  final PushPlatform _platform;
  final PushRegistration _registration;
  final ChatSession _session;
  final Locale Function() _locale;

  /// False when this build has no push gateway.
  final bool enabled;

  late final status =
      (enabled ? PushStatus.pending : PushStatus.notConfigured).obs;

  /// A conversation to open because the user tapped its notification. The
  /// conversation list consumes it.
  final openRequest = RxnString();

  final _subscriptions = <StreamSubscription<Object?>>[];

  /// What was last registered (user, token, language), to skip repeats.
  String? _registered;
  Future<void>? _refreshing;
  bool _again = false;

  @override
  void onInit() {
    super.onInit();
    if (!enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.addAll([
      _session.sessionState.listen(_onSession),
      _platform.tokenChanges.listen((_) => updateRegistration(force: true)),
      _platform.openedConversations.listen((room) => openRequest.value = room),
    ]);
    unawaited(_takeColdStartTap());
  }

  Future<void> _takeColdStartTap() async {
    try {
      final room = await _platform.takeOpenedConversation();
      if (room != null && room.isNotEmpty) openRequest.value = room;
    } catch (_) {
      // No pending tap.
    }
  }

  void _onSession(SessionState state) {
    if (state.isSignedIn) {
      unawaited(updateRegistration());
    } else if (state.status == SessionStatus.signedOut) {
      // Synapse removes the pusher when the device signs out.
      _registered = null;
      status.value = PushStatus.pending;
    }
  }

  /// Registers (again) when signed in and something changed, or always with
  /// [force]. Safe to call often.
  Future<void> updateRegistration({bool force = false}) {
    if (!enabled) return Future.value();
    final running = _refreshing;
    if (running != null) {
      // Something changed during the current run (for example a new token):
      // run once more afterwards.
      _again = _again || force;
      return running;
    }
    return _refreshing = _refresh(force: force).whenComplete(() {
      _refreshing = null;
      if (_again) {
        _again = false;
        unawaited(updateRegistration(force: true));
      }
    });
  }

  Future<void> _refresh({required bool force}) async {
    final user = _session.currentSessionState.user;
    if (!_session.currentSessionState.isSignedIn || user == null) return;
    try {
      if (!await _platform.requestPermission()) {
        status.value = PushStatus.denied;
        return;
      }
      final token = await _platform.token();
      if (token == null) {
        status.value = PushStatus.unavailable;
        return;
      }
      final locale = _locale();
      final key = '${user.id.value}|${token.value}|${locale.languageCode}';
      if (!force && key == _registered) {
        status.value = PushStatus.on;
        return;
      }
      final text = lookupAppLocalizations(locale).pushNewMessage;
      await _platform.setAlertText(text);
      await _registration.registerPush(
        token,
        alertText: text,
        languageCode: locale.languageCode,
      );
      _registered = key;
      status.value = PushStatus.on;
    } on ChatFailure {
      status.value = PushStatus.unavailable;
    } catch (_) {
      // Platform channel errors.
      status.value = PushStatus.unavailable;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_platform.clearDelivered().catchError((Object _) {}));
    // Picks up a permission granted in the system settings meanwhile.
    unawaited(updateRegistration());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.onClose();
  }
}
