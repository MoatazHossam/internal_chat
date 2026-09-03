import '../models/api_result.dart';
import '../models/authentication.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/file_models.dart';
import '../models/page_result.dart';
import '../models/user.dart';
import '../web_services/api_contract_placeholders.dart';
import 'authentication_repository.dart';
import 'chat_repository.dart';
import 'file_repository.dart';

// These placeholders deliberately return a pending error until the backend
// team provides approved API contracts. Do not add real implementation here
// without an approved API specification.

ApiFailure<T> _pending<T>() => const ApiFailure(
      ApiError(ApiErrorKind.unknown, 'Backend contract is not configured'),
    );

class RestAuthenticationRepository implements AuthenticationRepository {
  RestAuthenticationRepository(this.api);

  final AuthenticationApi api;

  @override
  Future<User?> currentUser() async => null;

  @override
  Future<ApiResult<AuthenticationOutcome>> signIn({
    required String identifier,
    required String password,
  }) async =>
      _pending();

  @override
  Future<void> signOut() async {}

  @override
  Future<ApiResult<Authenticated>> verifyMfa({
    required String challengeId,
    required String code,
  }) async =>
      _pending();
}

class RestChatRepository implements ChatRepository {
  RestChatRepository(this.api);

  final ChatApi api;

  @override
  Stream<ChatMessage> get incomingMessages => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<ApiResult<PageResult<Conversation>>> conversations(
    PageRequest request,
  ) async =>
      _pending();

  @override
  Future<ApiResult<PageResult<ChatMessage>>> messages(
    String conversationId,
    PageRequest request,
  ) async =>
      _pending();

  @override
  Future<ApiResult<ChatMessage>> sendMessage({
    required String conversationId,
    required String body,
    required String clientId,
    String? replyToId,
    String? replyToSenderName,
    String? replyToBody,
    String? attachmentName,
    String? attachmentMimeType,
    int? attachmentDurationMs,
    String? attachmentLocalPath,
  }) async =>
      _pending();
}

class RestFileRepository implements FileRepository {
  RestFileRepository(this.api);

  final FileApi api;

  @override
  Future<ApiResult<UploadedFile>> upload(FileSelection file) async =>
      const ApiFailure(
        ApiError(ApiErrorKind.unknown, 'Backend contract is not configured'),
      );
}
