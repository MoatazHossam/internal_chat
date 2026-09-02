import 'contracts.dart';

/// Placeholder awaiting the approved SignalR hub URL, authentication method,
/// and event contract from the backend team. Do not implement event parsing
/// here until the backend contract is supplied.
abstract interface class SignalRTransport {
  Stream<Object?> get events;
  Future<void> start();
  Future<void> stop();
}

class SignalRRealtimeService implements RealtimeService {
  SignalRRealtimeService(this.transport);

  final SignalRTransport transport;

  @override
  Stream<RealtimeEvent> get events => const Stream.empty();

  @override
  Future<void> connect() => transport.start();

  @override
  Future<void> disconnect() => transport.stop();
}
