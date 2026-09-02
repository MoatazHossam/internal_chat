class User {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final String role; // 'admin' | 'member'

  const User({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.role = 'member',
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        avatarUrl: j['avatar_url'] as String?,
        role: j['role'] as String? ?? 'member',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'avatar_url': avatarUrl,
        'role': role,
      };
}
