import '../l10n/app_localizations.dart';
import '../models/chat_message.dart';

/// Short text for a message in previews (conversation list, reply bars).
/// Text messages show their body; other kinds a localized label.
String messagePreviewText(
  AppLocalizations l10n,
  MessageKind kind,
  String body, {
  String? attachmentName,
}) => switch (kind) {
  MessageKind.text => body,
  MessageKind.image => '📷 ${l10n.photo}',
  MessageKind.file => '📎 ${attachmentName ?? l10n.file}',
  MessageKind.voice || MessageKind.audio => '🎤 ${l10n.voiceMessage}',
  MessageKind.deleted => l10n.deletedMessage,
  MessageKind.undecryptable => '🔒 ${l10n.encryptedMessage}',
  MessageKind.unsupported => l10n.unsupportedMessage,
};
