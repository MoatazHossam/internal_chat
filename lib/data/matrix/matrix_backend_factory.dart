import '../../domain/chat_backend.dart';
import 'matrix_chat_backend.dart';

ChatBackend createMatrixBackend(Uri homeserver) =>
    MatrixChatBackend(homeserver: homeserver);
