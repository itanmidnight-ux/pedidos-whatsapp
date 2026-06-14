class Message {
  final int?    id;
  final String  phone;
  final String? customerName;
  final String  content;
  final String  direction;
  final int     sent;
  final bool    flagged;
  final String? flagReason;
  final String  createdAt;
  final String? mediaType; // 'audio' | 'image' | null
  final String? mediaUrl;  // filename served via /api/messages/media/:filename

  Message({
    this.id, required this.phone, this.customerName,
    required this.content, required this.direction,
    this.sent = 0, this.flagged = false, this.flagReason,
    required this.createdAt, this.mediaType, this.mediaUrl,
  });

  bool get isOutbound  => direction == 'outbound';
  bool get isAudio     => mediaType == 'audio';
  bool get isImage     => mediaType == 'image';
  bool get isMediaMsg  => mediaType != null;

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id:           j['id'],
    phone:        j['phone'] ?? '',
    customerName: j['customer_name'],
    content:      j['content'] ?? '',
    direction:    j['direction'] ?? 'inbound',
    sent:         j['sent'] ?? 0,
    flagged:      j['flagged'] == 1 || j['flagged'] == true,
    flagReason:   j['flag_reason'],
    createdAt:    j['created_at'] ?? '',
    mediaType:    j['media_type'],
    mediaUrl:     j['media_url'],
  );
}

class Conversation {
  final String  phone;
  final String? customerName;
  final String? lastMsg;
  final String? lastAt;
  final String? lastMediaType;
  final int     unread;
  final int     flaggedCount;
  final String? flagReason;
  final String? profilePicUrl;
  final bool    archived;

  Conversation({
    required this.phone, this.customerName,
    this.lastMsg, this.lastAt, this.lastMediaType,
    this.unread = 0, this.flaggedCount = 0, this.flagReason,
    this.profilePicUrl, this.archived = false,
  });

  String get displayName {
    if (customerName != null && customerName!.isNotEmpty) return customerName!;
    final p = phone.replaceAll(RegExp(r'\D'), '');
    if (p.length == 12 && p.startsWith('57')) {
      return '+57 ${p.substring(2, 5)} ${p.substring(5, 8)} ${p.substring(8)}';
    }
    if (p.length >= 7) return '+$p';
    return phone;
  }
  bool   get hasFlaggedMessages => flaggedCount > 0;

  String get lastMsgPreview {
    if (lastMediaType == 'audio') return '🎵 Mensaje de voz';
    if (lastMediaType == 'image') return '📷 Imagen';
    return lastMsg ?? '';
  }

  String get flagLabel {
    switch (flagReason) {
      case 'reclamo':         return '🚨 Reclamo';
      case 'fiado_bloqueado': return '⚠️ Fiado bloqueado';
      case 'fiado_pedido':    return '💳 Pedido fiado';
      default:                return '🔔 Alerta';
    }
  }

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    phone:         j['phone'] ?? '',
    customerName:  j['customer_name'],
    lastMsg:       j['last_msg'],
    lastAt:        j['last_at'],
    lastMediaType: j['last_media_type'],
    unread:        j['unread'] ?? 0,
    flaggedCount:  j['flagged_count'] ?? 0,
    flagReason:    j['flag_reason'],
    profilePicUrl: j['profile_pic_url'],
    archived:      (j['archived'] ?? 0) == 1,
  );
}
