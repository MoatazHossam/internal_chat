import 'dart:async';
import 'package:get/get.dart';
import '../models/message.dart';

enum SocketState { disconnected, connecting, connected }

class SocketEvent {
  final String type;
  final String channelId;
  final Map<String, dynamic> data;

  const SocketEvent({
    required this.type,
    required this.channelId,
    required this.data,
  });
}

class SocketService extends GetxService {
  final _controller = StreamController<SocketEvent>.broadcast();
  final connectionState = SocketState.disconnected.obs;
  Timer? _pingTimer;

  Future<void> connect() async {
    if (connectionState.value == SocketState.connected) return;
    connectionState.value = SocketState.connecting;
    // Simulate connection delay
    await Future.delayed(const Duration(milliseconds: 500));
    connectionState.value = SocketState.connected;
    _startPing();
  }

  void _startPing() {
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      // ping in real implementation
    });
  }

  Stream<SocketEvent> messagesFor(String channelId) =>
      _controller.stream.where((e) => e.channelId == channelId);

  void sendTyping(String channelId) {
    // In real impl, send typing event over WebSocket
  }

  /// Simulate an incoming message (for demo/testing)
  void simulateIncoming(Message msg) {
    _controller.add(SocketEvent(
      type: 'new_message',
      channelId: msg.channelId,
      data: {
        'id': msg.id,
        'channel_id': msg.channelId,
        'sender_id': msg.senderId,
        'sender_name': msg.senderName,
        'text': msg.text,
        'attachments': [],
        'created_at': msg.createdAt.toIso8601String(),
      },
    ));
  }

  void disconnect() {
    _pingTimer?.cancel();
    connectionState.value = SocketState.disconnected;
  }

  @override
  void onClose() {
    disconnect();
    _controller.close();
    super.onClose();
  }
}
