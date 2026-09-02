import 'dart:async';

import '../models/chat_message.dart';
import 'contracts.dart';

class MockRealtimeService implements RealtimeService {
  final _controller = StreamController<RealtimeEvent>.broadcast();

  @override
  Stream<RealtimeEvent> get events => _controller.stream;

  void emit(RealtimeEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  void dispose() {
    _controller.close();
  }
}

class MemoryLocalChatStorageService implements LocalChatStorageService {
  final _data = <String, List<ChatMessage>>{};

  @override
  Future<List<ChatMessage>> readMessages(String conversationId) async {
    return List.unmodifiable(_data[conversationId] ?? []);
  }

  @override
  Future<void> saveMessages(
    String conversationId,
    List<ChatMessage> messages,
  ) async {
    _data[conversationId] = List.of(messages);
  }
}

class MemoryOutboxService implements OutboxService {
  final _items = <ChatMessage>[];

  @override
  Future<void> enqueue(ChatMessage message) async => _items.add(message);

  @override
  Future<List<ChatMessage>> pending() async => List.unmodifiable(_items);

  @override
  Future<void> remove(String messageId) async {
    _items.removeWhere((m) => m.id == messageId);
  }
}

class MockConnectivityService implements ConnectivityService {
  MockConnectivityService({this.online = true});

  bool online;

  @override
  Stream<bool> get changes => Stream.value(online);

  @override
  Future<bool> get isOnline async => online;
}
