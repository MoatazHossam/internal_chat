import 'package:uuid/uuid.dart';

enum MessageStatus { sending, sent, failed }
enum MessageType   { normal, viewOnce, otpLocked }
enum MediaType     { voice, image, video }

// ─── MediaAttachment ─────────────────────────────────────────────────────────

class MediaAttachment {
  final MediaType type;
  /// Local file path (for images/videos picked from device)
  final String? localPath;
  /// Voice note duration in seconds
  final int durationSeconds;

  const MediaAttachment({
    required this.type,
    this.localPath,
    this.durationSeconds = 0,
  });

  Map<String, dynamic> toJson() => {
        'media_type': type.name,
        'local_path': localPath,
        'duration_seconds': durationSeconds,
      };

  factory MediaAttachment.fromJson(Map<String, dynamic> j) => MediaAttachment(
        type: MediaType.values.firstWhere(
          (t) => t.name == j['media_type'],
          orElse: () => MediaType.image,
        ),
        localPath: j['local_path'] as String?,
        durationSeconds: j['duration_seconds'] as int? ?? 0,
      );
}

// ─── Message ─────────────────────────────────────────────────────────────────

class Message {
  final String id;
  final String channelId;
  final String senderId;
  final String senderName;
  final String text;
  final List<MessageAttachment> attachments;
  final MediaAttachment? media;
  final DateTime createdAt;
  final MessageStatus status;
  final MessageType type;
  final bool viewed;
  final bool unlocked;
  final String? otpCode;

  const Message({
    required this.id,
    required this.channelId,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.attachments = const [],
    this.media,
    required this.createdAt,
    this.status   = MessageStatus.sent,
    this.type     = MessageType.normal,
    this.viewed   = false,
    this.unlocked = false,
    this.otpCode,
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id:         j['id']          as String,
        channelId:  j['channel_id']  as String,
        senderId:   j['sender_id']   as String,
        senderName: j['sender_name'] as String,
        text:       j['text']        as String? ?? '',
        attachments: (j['attachments'] as List<dynamic>? ?? [])
            .map((a) => MessageAttachment.fromJson(a as Map<String, dynamic>))
            .toList(),
        media: j['media'] != null
            ? MediaAttachment.fromJson(j['media'] as Map<String, dynamic>)
            : null,
        createdAt: DateTime.parse(j['created_at'] as String),
        status:    MessageStatus.sent,
        type:      typeFromString(j['type'] as String?),
        viewed:    j['viewed']   as bool? ?? false,
        unlocked:  j['unlocked'] as bool? ?? false,
        otpCode:   j['otp_code'] as String?,
      );

  factory Message.optimistic({
    required String channelId,
    String text       = '',
    String senderId   = 'me',
    String senderName = 'You',
    MessageType type  = MessageType.normal,
    String? otpCode,
    MediaAttachment? media,
  }) =>
      Message(
        id:         'optimistic_${const Uuid().v4()}',
        channelId:  channelId,
        senderId:   senderId,
        senderName: senderName,
        text:       text,
        media:      media,
        createdAt:  DateTime.now(),
        status:     MessageStatus.sending,
        type:       type,
        otpCode:    otpCode,
      );

  Message copyWith({
    MessageStatus?   status,
    String?          id,
    bool?            viewed,
    bool?            unlocked,
    MessageType?     type,
  }) =>
      Message(
        id:          id       ?? this.id,
        channelId:   channelId,
        senderId:    senderId,
        senderName:  senderName,
        text:        text,
        attachments: attachments,
        media:       media,
        createdAt:   createdAt,
        status:      status   ?? this.status,
        type:        type     ?? this.type,
        viewed:      viewed   ?? this.viewed,
        unlocked:    unlocked ?? this.unlocked,
        otpCode:     otpCode,
      );

  static MessageType typeFromString(String? s) => switch (s) {
    'view_once'  => MessageType.viewOnce,
    'otp_locked' => MessageType.otpLocked,
    _            => MessageType.normal,
  };

  String get typeString => switch (type) {
    MessageType.viewOnce  => 'view_once',
    MessageType.otpLocked => 'otp_locked',
    MessageType.normal    => 'normal',
  };
}

// ─── File attachment (for documents) ─────────────────────────────────────────

class MessageAttachment {
  final String id;
  final String fileName;
  final int    fileSize;
  final String mimeType;

  const MessageAttachment({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
  });

  factory MessageAttachment.fromJson(Map<String, dynamic> j) =>
      MessageAttachment(
        id:       j['id']        as String,
        fileName: j['file_name'] as String,
        fileSize: j['file_size'] as int,
        mimeType: j['mime_type'] as String,
      );
}
