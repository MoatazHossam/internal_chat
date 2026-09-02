import 'contracts.dart';
/// Placeholder awaiting approved hub URL, authentication and event contracts.
abstract interface class SignalRTransport { Stream<Object?> get events; Future<void> start(); Future<void> stop(); }
class SignalRRealtimeService implements RealtimeService { SignalRRealtimeService(this.transport); final SignalRTransport transport; @override Stream<RealtimeEvent> get events=>const Stream.empty(); @override Future<void> connect()=>transport.start(); @override Future<void> disconnect()=>transport.stop(); }
