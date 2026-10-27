import '../constants.dart';
import '../domain/chat_backend.dart';
import 'unsupported_platform_backend.dart'
    if (dart.library.io) 'matrix/matrix_backend_factory.dart';

/// Composition root for the backend: the only place that picks the
/// implementation behind the domain contracts. Pages and controllers never
/// know which one they talk to.
ChatBackend createChatBackend(AppConfiguration configuration) =>
    createMatrixBackend(configuration.homeserver, push: configuration.push);
