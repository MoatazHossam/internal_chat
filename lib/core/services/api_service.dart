import 'package:get/get.dart';
import '../models/user.dart';
import '../models/channel.dart';
import '../models/message.dart';

sealed class ApiResult<T> {
  const ApiResult();
}

class ApiSuccess<T> extends ApiResult<T> {
  final T data;
  const ApiSuccess(this.data);
}

class ApiError<T> extends ApiResult<T> {
  final String message;
  final int? statusCode;
  const ApiError(this.message, {this.statusCode});
}

/// Dummy data store shared across the service
class _DummyStore {
  // Logged-in user is Moataz (u1)
  static final users = [
    User(id: 'u1',   name: 'Moataz Hossam',      email: 'moataz@company.ae', role: 'admin'),
    User(id: 'u2',   name: 'Omar Ahmed',          email: 'omar@company.ae'),
    User(id: 'u3',   name: 'Seif Mohammed',       email: 'seif@company.ae'),
    User(id: 'u_ob', name: 'خالد - الخدمات',     email: 'khaled@company.ae'),
  ];

  static final channels = [
    // Public rooms
    Channel(id: 'c1', name: 'الإدارة',        description: 'قناة الإدارة العليا',     type: 'public', memberCount: 12, lastMessage: 'أهلاً وسهلاً بالجميع!',      lastMessageAt: DateTime.now().subtract(const Duration(minutes: 5)),  unreadCount: 3),
    Channel(id: 'c2', name: 'قسم التحليل',   description: 'فريق تحليل البيانات',    type: 'public', memberCount: 18, lastMessage: 'الـ PR جاهز للمراجعة',       lastMessageAt: DateTime.now().subtract(const Duration(hours: 1)),    unreadCount: 0),
    Channel(id: 'c3', name: 'الموارد البشرية', description: 'قسم الموارد البشرية',  type: 'public', memberCount: 8,  lastMessage: 'تم رفع الـ mockups الجديدة',  lastMessageAt: DateTime.now().subtract(const Duration(hours: 2)),    unreadCount: 1),
    Channel(id: 'c4', name: 'عام',           description: 'النقاشات العامة',        type: 'public', memberCount: 100, lastMessage: '😂',                        lastMessageAt: DateTime.now().subtract(const Duration(days: 1)),     unreadCount: 4),
    Channel(id: 'c5', name: 'IT',            description: 'قسم تقنية المعلومات',    type: 'public', memberCount: 20, lastMessage: 'نتائج الربع الأول متاحة',    lastMessageAt: DateTime.now().subtract(const Duration(days: 2)),     unreadCount: 0),
    // Direct messages (dm_participant = the other person)
    Channel(id: 'dm_u2', name: 'Omar Ahmed',       type: 'direct', lastMessage: 'شكراً جزيلاً!',      lastMessageAt: DateTime.now().subtract(const Duration(minutes: 20)), unreadCount: 1, dmParticipantName: 'Omar Ahmed',       dmParticipantId: 'u2'),
    Channel(id: 'dm_u3', name: 'Seif Mohammed',    type: 'direct', lastMessage: 'هل الاجتماع غداً؟', lastMessageAt: DateTime.now().subtract(const Duration(hours: 3)),    unreadCount: 0, dmParticipantName: 'Seif Mohammed',    dmParticipantId: 'u3'),
    Channel(id: 'dm_ob', name: 'خالد - الخدمات', type: 'direct', lastMessage: 'في خدمتكم دائماً 🫖', lastMessageAt: DateTime.now().subtract(const Duration(hours: 1)),    unreadCount: 0, dmParticipantName: 'خالد - الخدمات', dmParticipantId: 'u_ob'),
  ];

  static final Map<String, List<Message>> messages = {
    'c1': [
      Message(id: 'm1',  channelId: 'c1', senderId: 'u1', senderName: 'Moataz Hossam', text: 'أهلاً بالجميع في قناة الإدارة 👋',                             createdAt: DateTime.now().subtract(const Duration(minutes: 30))),
      Message(id: 'm2',  channelId: 'c1', senderId: 'u2', senderName: 'Omar Ahmed',    text: 'جاهزون لاجتماع مجلس الإدارة الأسبوعي.',                        createdAt: DateTime.now().subtract(const Duration(minutes: 25))),
      Message(id: 'm3',  channelId: 'c1', senderId: 'u3', senderName: 'Seif Mohammed', text: 'تمت مراجعة تقارير الربع الأول.',                                createdAt: DateTime.now().subtract(const Duration(minutes: 20))),
      Message(id: 'm4',  channelId: 'c1', senderId: 'u2', senderName: 'Omar Ahmed',    text: 'هل تمت الموافقة على الميزانية الجديدة؟',                        createdAt: DateTime.now().subtract(const Duration(minutes: 15))),
      Message(id: 'm5',  channelId: 'c1', senderId: 'u1', senderName: 'Moataz Hossam', text: 'نعم، سيتم الإعلان رسمياً الأسبوع القادم إن شاء الله.',         createdAt: DateTime.now().subtract(const Duration(minutes: 10))),
      Message(id: 'm6',  channelId: 'c1', senderId: 'u3', senderName: 'Seif Mohammed', text: 'أهلاً وسهلاً بالجميع!',                                        createdAt: DateTime.now().subtract(const Duration(minutes: 5))),
    ],
    'c2': [
      Message(id: 'm7',  channelId: 'c2', senderId: 'u3', senderName: 'Seif Mohammed', text: 'انتهينا من تحليل بيانات المبيعات للربع الأول.',       createdAt: DateTime.now().subtract(const Duration(hours: 3))),
      Message(id: 'm8',  channelId: 'c2', senderId: 'u1', senderName: 'Moataz Hossam', text: 'ممتاز! هل النتائج جاهزة للعرض؟',                      createdAt: DateTime.now().subtract(const Duration(hours: 2))),
      Message(id: 'm9',  channelId: 'c2', senderId: 'u3', senderName: 'Seif Mohammed', text: 'الـ PR جاهز للمراجعة',                                createdAt: DateTime.now().subtract(const Duration(hours: 1))),
    ],
    'c3': [
      Message(id: 'm10', channelId: 'c3', senderId: 'u2', senderName: 'Omar Ahmed',    text: 'تم رفع نماذج عقود التوظيف الجديدة للمراجعة.',         createdAt: DateTime.now().subtract(const Duration(hours: 2))),
    ],
    'c4': [
      Message(id: 'm11', channelId: 'c4', senderId: 'u1', senderName: 'Moataz Hossam', text: 'صباح الخير جميعاً ☀️',                               createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 2))),
      Message(id: 'm12', channelId: 'c4', senderId: 'u2', senderName: 'Omar Ahmed',    text: 'صباح النور 😂',                                        createdAt: DateTime.now().subtract(const Duration(days: 1))),
    ],
    'c5': [
      Message(id: 'm13', channelId: 'c5', senderId: 'u1', senderName: 'Moataz Hossam', text: 'تم تحديث الخوادم بنجاح، لا توجد مشاكل حتى الآن. ✅',   createdAt: DateTime.now().subtract(const Duration(days: 2))),
    ],
    // Office boy DM
    'dm_ob': [
      Message(id: 'mob1', channelId: 'dm_ob', senderId: 'u_ob', senderName: 'خالد - الخدمات', text: 'السلام عليكم! في خدمتكم دائماً 🫖', createdAt: DateTime.now().subtract(const Duration(hours: 1))),
    ],
    // DMs
    'dm_u2': [
      Message(id: 'm20', channelId: 'dm_u2', senderId: 'u2', senderName: 'Omar Ahmed',    text: 'مرحباً موتاز، هل راجعت الميزانية الجديدة؟',         createdAt: DateTime.now().subtract(const Duration(hours: 2))),
      Message(id: 'm21', channelId: 'dm_u2', senderId: 'u1', senderName: 'Moataz Hossam', text: 'نعم، راجعتها. تبدو جيدة.',                          createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 30))),
      // View-once message from Omar
      Message(id: 'm22vo', channelId: 'dm_u2', senderId: 'u2', senderName: 'Omar Ahmed',  text: 'كود الوصول للخادم: X9-Alpha-77',                    createdAt: DateTime.now().subtract(const Duration(minutes: 40)), type: MessageType.viewOnce),
      Message(id: 'm23', channelId: 'dm_u2', senderId: 'u2', senderName: 'Omar Ahmed',    text: 'شكراً جزيلاً!',                                     createdAt: DateTime.now().subtract(const Duration(minutes: 20))),
    ],
    'dm_u3': [
      Message(id: 'm30', channelId: 'dm_u3', senderId: 'u1', senderName: 'Moataz Hossam', text: 'سيف، هل أنهيت تقرير الأداء؟',                      createdAt: DateTime.now().subtract(const Duration(hours: 5))),
      Message(id: 'm31', channelId: 'dm_u3', senderId: 'u3', senderName: 'Seif Mohammed', text: 'نعم، سأرسله قريباً.',                               createdAt: DateTime.now().subtract(const Duration(hours: 4))),
      // OTP-locked message from Seif
      Message(id: 'm32otp', channelId: 'dm_u3', senderId: 'u3', senderName: 'Seif Mohammed', text: 'كلمة سر الخادم الجديد هي: Secure@UAE2026',        createdAt: DateTime.now().subtract(const Duration(hours: 3, minutes: 30)), type: MessageType.otpLocked, otpCode: '847291'),
      Message(id: 'm33', channelId: 'dm_u3', senderId: 'u3', senderName: 'Seif Mohammed', text: 'هل الاجتماع غداً؟',                                 createdAt: DateTime.now().subtract(const Duration(hours: 3))),
    ],
  };
}

class ApiService extends GetxService {
  // Simulates authenticated user (alice)
  User? _currentUser;
  int _msgCounter = 100;

  String _nextMsgId() => 'm${_msgCounter++}';

  Future<ApiResult<T>> get<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _handleGet(path, fromJson);
  }

  Future<ApiResult<T>> post<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _handlePost(path, body, fromJson);
  }

  Future<ApiResult<T>> put<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return ApiSuccess(fromJson({}));
  }

  Future<ApiResult<void>> delete(String path) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return const ApiSuccess(null);
  }

  ApiResult<T> _handleGet<T>(
      String path, T Function(Map<String, dynamic>) fromJson) {
    if (path == '/auth/me') {
      if (_currentUser != null) {
        return ApiSuccess(fromJson(_currentUser!.toJson())) as ApiResult<T>;
      }
      return ApiError('Unauthorized', statusCode: 401);
    }

    // GET /channels
    if (path == '/channels') {
      final data = {
        'channels': _DummyStore.channels.map((c) => {
              'id': c.id,
              'name': c.name,
              'description': c.description,
              'type': c.type,
              'member_count': c.memberCount,
              'last_message': c.lastMessage,
              'last_message_at': c.lastMessageAt?.toIso8601String(),
              'unread_count': c.unreadCount,
              'dm_participant_name': c.dmParticipantName,
              'dm_participant_id': c.dmParticipantId,
            }).toList(),
      };
      return ApiSuccess(fromJson(data)) as ApiResult<T>;
    }

    // GET /channels/:id/messages
    final msgMatch = RegExp(r'/channels/(\w+)/messages').firstMatch(path);
    if (msgMatch != null) {
      final channelId = msgMatch.group(1)!;
      final msgs = _DummyStore.messages[channelId] ?? [];
      final data = {
        'messages': msgs.reversed.take(50).map((m) => {
              'id': m.id,
              'channel_id': m.channelId,
              'sender_id': m.senderId,
              'sender_name': m.senderName,
              'text': m.text,
              'type': m.typeString,
              'otp_code': m.otpCode,
              'attachments': [],
              'created_at': m.createdAt.toIso8601String(),
            }).toList(),
      };
      return ApiSuccess(fromJson(data)) as ApiResult<T>;
    }

    return ApiError('Not found', statusCode: 404);
  }

  ApiResult<T> _handlePost<T>(String path, Map<String, dynamic> body,
      T Function(Map<String, dynamic>) fromJson) {
    // Login
    if (path == '/auth/login') {
      final email = body['email'] as String;
      final user = _DummyStore.users.firstWhereOrNull((u) => u.email == email);
      if (user == null) {
        return ApiError('Invalid credentials', statusCode: 401);
      }
      _currentUser = user;
      final data = {
        'access_token': 'dummy_access_token_${user.id}',
        'refresh_token': 'dummy_refresh_token_${user.id}',
        'user': user.toJson(),
        'requires_mfa': false,
      };
      return ApiSuccess(fromJson(data)) as ApiResult<T>;
    }

    // Logout
    if (path == '/auth/logout') {
      _currentUser = null;
      return ApiSuccess(fromJson({})) as ApiResult<T>;
    }

    // Send message
    final msgMatch = RegExp(r'/channels/(\w+)/messages$').firstMatch(path);
    if (msgMatch != null) {
      final channelId = msgMatch.group(1)!;
      final typeStr = body['type'] as String? ?? 'normal';
      final msg = Message(
        id: _nextMsgId(),
        channelId: channelId,
        senderId: _currentUser?.id ?? 'me',
        senderName: _currentUser?.name ?? 'You',
        text: body['text'] as String? ?? '',
        createdAt: DateTime.now(),
        status: MessageStatus.sent,
        type: Message.typeFromString(typeStr),
        otpCode: body['otp_code'] as String?,
      );
      _DummyStore.messages.putIfAbsent(channelId, () => []);
      _DummyStore.messages[channelId]!.add(msg);
      final data = {
        'id': msg.id,
        'channel_id': msg.channelId,
        'sender_id': msg.senderId,
        'sender_name': msg.senderName,
        'text': msg.text,
        'type': msg.typeString,
        'otp_code': msg.otpCode,
        if (msg.media != null) 'media': msg.media!.toJson(),
        'attachments': [],
        'created_at': msg.createdAt.toIso8601String(),
      };
      return ApiSuccess(fromJson(data)) as ApiResult<T>;
    }

    // Mark read
    if (path.endsWith('/read')) {
      return ApiSuccess(fromJson({})) as ApiResult<T>;
    }

    // File upload init
    if (path == '/files/upload/init') {
      return ApiSuccess(fromJson({'upload_id': 'upload_${DateTime.now().millisecondsSinceEpoch}'})) as ApiResult<T>;
    }

    // File upload complete
    if (path == '/files/upload/complete') {
      return ApiSuccess(fromJson({'file_id': 'file_${DateTime.now().millisecondsSinceEpoch}'})) as ApiResult<T>;
    }

    return ApiSuccess(fromJson({})) as ApiResult<T>;
  }

  // Post multipart (for chunk uploads)
  Future<int> postChunk({
    required String uploadId,
    required int chunkIndex,
    required int totalChunks,
    required List<int> bytes,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return 200; // Always succeeds in dummy mode
  }
}

extension IterableExtension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
