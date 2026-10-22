import '../domain/ids.dart';

/// The signed-in account. The server has presence disabled, so there is no
/// online/last-seen information to model.
class User {
  const User({required this.id, required this.displayName, this.deviceId});

  final UserId id;
  final String displayName;

  /// This sign-in's device. Each sign-in creates a new device with its own
  /// encryption keys.
  final String? deviceId;
}
