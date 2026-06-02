class Message {
  final int? id;
  final String phone;
  final String? customerName;
  final String content;
  final String direction;
  final int sent;
  final bool flagged;
  final String? flagReason;
  final String createdAt;

  Message({
    this.id, required this.phone, this.customerName,
    required this.content, required this.direction,
    this.sent = 0, this.flagged = false, this.flagReason,
    required this.createdAt,
  });

  bool get isOutbound => direction == 'outbound';

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id: j['id'], phone: j['phone'] ?? '',
    customerName: j['customer_name'],
    content: j['content'] ?? '',
    direction: j['direction'] ?? 'inbound',
    sent: j['sent'] ?? 0,
    flagged: j['flagged'] == 1 || j['flagged'] == true,
    flagReason: j['flag_reason'],
    createdAt: j['created_at'] ?? '',
  );
}

class Conversation {
  final String phone;
  final String? customerName;
  final String? lastMsg;
  final String? lastAt;
  final int unread;
  final int flaggedCount;
  final String? flagReason;

  Conversation({
    required this.phone, this.customerName,
    this.lastMsg, this.lastAt, this.unread = 0,
    this.flaggedCount = 0, this.flagReason,
  });

  String get displayName => customerName ?? phone;
  bool get hasFlaggedMessages => flaggedCount > 0;

  String get flagLabel {
    switch (flagReason) {
      case 'reclamo':         return '🚨 Reclamo';
      case 'fiado_bloqueado': return '⚠️ Fiado bloqueado';
      case 'fiado_pedido':    return '💳 Pedido fiado';
      default:                return '🔔 Alerta';
    }
  }

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    phone: j['phone'] ?? '',
    customerName: j['customer_name'],
    lastMsg: j['last_msg'],
    lastAt: j['last_at'],
    unread: j['unread'] ?? 0,
    flaggedCount: j['flagged_count'] ?? 0,
    flagReason: j['flag_reason'],
  );
}
