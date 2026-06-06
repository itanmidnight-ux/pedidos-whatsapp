class Estado {
  final int id;
  final String adminUsername;
  final String filename;
  final String mediaType;
  final String? caption;
  final DateTime createdAt;
  final DateTime expiresAt;

  Estado({
    required this.id,
    required this.adminUsername,
    required this.filename,
    required this.mediaType,
    this.caption,
    required this.createdAt,
    required this.expiresAt,
  });

  factory Estado.fromJson(Map<String, dynamic> j) => Estado(
    id:            j['id'],
    adminUsername: j['admin_username'],
    filename:      j['filename'],
    mediaType:     j['media_type'] ?? 'image',
    caption:       j['caption'],
    createdAt:     DateTime.parse(j['created_at']),
    expiresAt:     DateTime.parse(j['expires_at']),
  );

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
