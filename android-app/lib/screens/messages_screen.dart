import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Conversation> _convs = [];
  bool _loading = true;
  bool _showFlaggedOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { _convs = await ApiService.getConversations(); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) return DateFormat('HH:mm').format(dt);
    return DateFormat('dd/MM').format(dt);
  }

  Color _flagColor(String? reason) {
    switch (reason) {
      case 'reclamo':         return Colors.red;
      case 'fiado_bloqueado': return Colors.orange;
      case 'fiado_pedido':    return const Color(0xFFD4800A);
      default:                return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _showFlaggedOnly
        ? _convs.where((c) => c.hasFlaggedMessages).toList()
        : _convs;

    final alertCount = _convs.where((c) => c.hasFlaggedMessages).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4EE),
      body: Column(children: [
        // ── Filtro de alertas ────────────────────────────────
        if (alertCount > 0)
          Container(
            color: Colors.red.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '$alertCount conversación(es) requieren atención',
                style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
              )),
              GestureDetector(
                onTap: () => setState(() => _showFlaggedOnly = !_showFlaggedOnly),
                child: Text(
                  _showFlaggedOnly ? 'Ver todas' : 'Ver alertas',
                  style: const TextStyle(color: Colors.red, fontSize: 12, decoration: TextDecoration.underline),
                ),
              ),
            ]),
          ),
        // ── Lista ────────────────────────────────────────────
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2D5016)))
          : displayed.isEmpty
            ? Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_showFlaggedOnly ? '✅' : '💬',
                    style: const TextStyle(fontSize: 56)),
                  const SizedBox(height: 12),
                  Text(
                    _showFlaggedOnly ? 'Sin alertas pendientes' : 'Sin conversaciones aún',
                    style: const TextStyle(color: Colors.grey, fontSize: 15)),
                ]))
            : RefreshIndicator(
                onRefresh: _load,
                color: const Color(0xFF2D5016),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: displayed.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72, endIndent: 16),
                  itemBuilder: (ctx, i) {
                    final c = displayed[i];
                    final flagColor = _flagColor(c.flagReason);
                    return ListTile(
                      leading: Stack(children: [
                        CircleAvatar(
                          backgroundColor: c.hasFlaggedMessages
                              ? flagColor : const Color(0xFF2D5016),
                          radius: 24,
                          child: Text(
                            c.displayName.isNotEmpty
                                ? c.displayName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        if (c.hasFlaggedMessages)
                          Positioned(right: 0, top: 0,
                            child: Container(
                              width: 14, height: 14,
                              decoration: BoxDecoration(
                                color: flagColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: const Icon(Icons.priority_high, size: 9, color: Colors.white),
                            )),
                      ]),
                      title: Row(children: [
                        Expanded(child: Text(c.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15))),
                        if (c.hasFlaggedMessages)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: flagColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(c.flagLabel,
                              style: TextStyle(fontSize: 10, color: flagColor,
                                fontWeight: FontWeight.bold)),
                          ),
                      ]),
                      subtitle: Text(
                        c.lastMsg ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_formatTime(c.lastAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: c.unread > 0 ? const Color(0xFF2D5016) : Colors.grey,
                            )),
                          if (c.unread > 0) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2D5016),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('${c.unread}',
                                style: const TextStyle(
                                  color: Colors.white, fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(ctx, MaterialPageRoute(
                          builder: (_) => ChatScreen(phone: c.phone, name: c.displayName)));
                        _load();
                      },
                    );
                  },
                ),
              )),
      ]),
    );
  }
}
