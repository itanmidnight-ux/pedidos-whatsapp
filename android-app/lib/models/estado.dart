class EstadoComment {
  final int id;
  final String username;
  final String displayName;
  final String comment;
  final DateTime createdAt;

  EstadoComment({
    required this.id,
    required this.username,
    required this.displayName,
    required this.comment,
    required this.createdAt,
  });

  factory EstadoComment.fromJson(Map<String, dynamic> j) => EstadoComment(
    id:          j['id'],
    username:    j['username'] ?? '',
    displayName: j['display_name'] ?? j['username'] ?? '',
    comment:     j['comment'] ?? '',
    createdAt:   DateTime.parse(j['created_at']),
  );
}

class Estado {
  final int id;
  final String adminUsername;
  final String filename;
  final String mediaType;
  final String? caption;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int heartCount;
  final bool hasHearted;
  final int commentCount;

  Estado({
    required this.id,
    required this.adminUsername,
    required this.filename,
    required this.mediaType,
    this.caption,
    required this.createdAt,
    required this.expiresAt,
    this.heartCount = 0,
    this.hasHearted = false,
    this.commentCount = 0,
  });

  factory Estado.fromJson(Map<String, dynamic> j) => Estado(
    id:           j['id'],
    adminUsername: j['admin_username'],
    filename:     j['filename'],
    mediaType:    j['media_type'] ?? 'image',
    caption:      j['caption'],
    createdAt:    DateTime.parse(j['created_at']),
    expiresAt:    DateTime.parse(j['expires_at']),
    heartCount:   (j['heart_count'] as num?)?.toInt() ?? 0,
    hasHearted:   j['has_hearted'] == true || j['has_hearted'] == 1,
    commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
  );

  Estado copyWith({int? heartCount, bool? hasHearted, int? commentCount}) => Estado(
    id: id, adminUsername: adminUsername, filename: filename,
    mediaType: mediaType, caption: caption,
    createdAt: createdAt, expiresAt: expiresAt,
    heartCount:   heartCount   ?? this.heartCount,
    hasHearted:   hasHearted   ?? this.hasHearted,
    commentCount: commentCount ?? this.commentCount,
  );

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 60)  return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24)    return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} días';
  }
}
