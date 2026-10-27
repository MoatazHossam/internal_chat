import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/push.dart';

/// The device side of push notifications: permission, the push token, and
/// notification taps. Implemented natively (`AppDelegate.swift` on iOS,
/// `MainActivity.kt` / `PushMessagingService.kt` on Android).
abstract interface class PushPlatform {
  /// Asks for permission to show notifications (once; later calls return
  /// the current answer).
  Future<bool> requestPermission();

  /// The current push token, or null when this build cannot receive pushes
  /// (for example an Android build without Firebase configuration).
  Future<PushToken?> token();

  /// New tokens issued by APNs or FCM.
  Stream<PushToken> get tokenChanges;

  /// Room IDs of notifications the user tapped while the app was running.
  Stream<String> get openedConversations;

  /// The room of a notification tapped before the app was ready (cold
  /// start), once.
  Future<String?> takeOpenedConversation();

  /// Removes delivered notifications (the user is looking at the app).
  Future<void> clearDelivered();

  /// The generic text Android shows for a new message, in the app's
  /// language. iOS receives it inside the push instead.
  Future<void> setAlertText(String text);
}

class MethodChannelPushPlatform implements PushPlatform {
  MethodChannelPushPlatform() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('internal_chat/push');

  final _tokens = StreamController<PushToken>.broadcast();
  final _opened = StreamController<String>.broadcast();

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'tokenChanged':
        final token = _parseToken(call.arguments);
        if (token != null) _tokens.add(token);
      case 'opened':
        final room = call.arguments;
        if (room is String && room.isNotEmpty) _opened.add(room);
    }
    return null;
  }

  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<PushToken?> token() async {
    try {
      return _parseToken(await _channel.invokeMethod<Object?>('getToken'));
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<PushToken> get tokenChanges => _tokens.stream;

  @override
  Stream<String> get openedConversations => _opened.stream;

  @override
  Future<String?> takeOpenedConversation() =>
      _channel.invokeMethod<String>('takeOpenedRoom');

  @override
  Future<void> clearDelivered() =>
      _channel.invokeMethod<void>('clearDelivered');

  @override
  Future<void> setAlertText(String text) =>
      _channel.invokeMethod<void>('setAlertText', {'text': text});

  static PushToken? _parseToken(Object? value) {
    if (value is! Map) return null;
    final token = value['token'];
    final service = switch (value['service']) {
      'apns' => PushService.apns,
      'fcm' => PushService.fcm,
      _ => null,
    };
    if (token is! String || token.isEmpty || service == null) return null;
    return PushToken(service, token);
  }
}
