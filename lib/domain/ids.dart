import 'package:uuid/uuid.dart';

/// Identifies a conversation (a Matrix room ID in the Matrix adapter).
extension type const ConversationId(String value) {}

/// Identifies a user (a full Matrix ID such as `@name:server`).
extension type const UserId(String value) {
  /// The server part of the ID, or an empty string when it has none.
  String get server {
    final index = value.indexOf(':');
    return index < 0 ? '' : value.substring(index + 1);
  }
}

/// Created once per user action (one tap on "send") and kept with the
/// pending message. Adapters derive their transport idempotency key from it,
/// so retrying the same message can never create a duplicate.
extension type const LocalMessageId(String value) {
  factory LocalMessageId.generate() => LocalMessageId(const Uuid().v4());
}

/// Points at one message inside one conversation.
class MessageRef {
  const MessageRef(this.conversationId, this.messageId);

  final ConversationId conversationId;
  final String messageId;

  @override
  bool operator ==(Object other) =>
      other is MessageRef &&
      other.conversationId == conversationId &&
      other.messageId == messageId;

  @override
  int get hashCode => Object.hash(conversationId, messageId);
}

final _userIdPattern = RegExp(r'^@[a-z0-9._=\-/+]+:[A-Za-z0-9.\-]+(:\d+)?$');

/// Accepts a full Matrix ID (`@name:server`), or a bare `name` / `@name`,
/// which is completed with [defaultServer]. Returns null when the result is
/// not a valid user ID.
UserId? parseUserId(String input, {required String defaultServer}) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.startsWith('@')) text = '@$text';
  if (!text.contains(':')) {
    if (defaultServer.isEmpty) return null;
    text = '$text:$defaultServer';
  }
  // Matrix localparts are lower case; servers are case-insensitive.
  final separator = text.indexOf(':');
  text = text.substring(0, separator).toLowerCase() + text.substring(separator);
  return _userIdPattern.hasMatch(text) ? UserId(text) : null;
}
