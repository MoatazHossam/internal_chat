class User {
  const User({
    required this.id,
    required this.displayName,
    required this.email,
    this.isOnline = false,
    this.lastSeen,
  });

  final String id;
  final String displayName;
  final String email;
  final bool isOnline;
  final DateTime? lastSeen;
}
