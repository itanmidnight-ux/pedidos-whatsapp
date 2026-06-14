import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Conversation> _chats    = [];
  List<Conversation> _archived = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.toLowerCase()));
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _silentRefresh());
  }

  Future<void> _silentRefresh() async {
    try {
      final results = await Future.wait([
        ApiService.getConversations(archived: false),
        ApiService.getConversations(archived: true),
      ]);
      if (mounted) setState(() { _chats = results[0]; _archived = results[1]; });
    } catch (_) {}
  }

  @override
  void dispose() { _tabs.dispose(); _searchCtrl.dispose(); _pollTimer?.cancel(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getConversations(archived: false),
        ApiService.getConversations(archived: true),
      ]);
      if (mounted) setState(() { _chats = results[0]; _archived = results[1]; });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) return DateFormat('HH:mm').format(dt);
    if (now.difference(dt).inDays < 7)  return DateFormat('EEE', 'es').format(dt);
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

  Future<void> _delete(Conversation c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar conversación'),
        content: Text('¿Borrar todos los mensajes con ${c.displayName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteConversation(c.phone);
      _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al borrar conversación')));
    }
  }

  Future<void> _archive(Conversation c, {required bool archive}) async {
    try {
      await ApiService.archiveConversation(c.phone, archived: archive);
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(archive ? 'Conversación archivada' : 'Conversación restaurada'),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () => ApiService.archiveConversation(c.phone, archived: !archive).then((_) => _load()),
          )));
    } catch (_) {}
  }

  Widget _buildAvatar(Conversation c) {
    final flagColor = _flagColor(c.flagReason);
    final initials = Text(
      c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?',
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
    );
    return Stack(children: [
      CircleAvatar(
        radius: 24,
        backgroundColor: c.hasFlaggedMessages ? flagColor : const Color(0xFF2D5016),
        child: c.profilePicUrl != null && c.profilePicUrl!.isNotEmpty
            ? ClipOval(child: CachedNetworkImage(
                imageUrl: c.profilePicUrl!,
                width: 48, height: 48, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => initials,
                placeholder: (_, __) => initials,
              ))
            : initials,
      ),
      if (c.hasFlaggedMessages)
        Positioned(right: 0, top: 0,
          child: Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: flagColor, shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5)),
            child: const Icon(Icons.priority_high, size: 9, color: Colors.white),
          )),
    ]);
  }

  Widget _buildConvTile(Conversation c, {bool isArchived = false}) {
    final flagColor = _flagColor(c.flagReason);
    return Slidable(
      key: ValueKey(c.phone),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.22,
        children: [
          SlidableAction(
            onPressed: (_) => _archive(c, archive: !isArchived),
            backgroundColor: Colors.amber.shade700,
            foregroundColor: Colors.white,
            icon: isArchived ? Icons.unarchive : Icons.archive,
            label: isArchived ? 'Restaurar' : 'Archivar',
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.22,
        children: [
          SlidableAction(
            onPressed: (_) => _delete(c),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'Borrar',
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
          ),
        ],
      ),
      child: ListTile(
        leading: _buildAvatar(c),
        title: Row(children: [
          Expanded(child: Text(c.displayName,
            style: TextStyle(
              fontWeight: c.unread > 0 ? FontWeight.w800 : FontWeight.w600,
              fontSize: 15))),
          if (c.hasFlaggedMessages)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: flagColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8)),
              child: Text(c.flagLabel,
                style: TextStyle(fontSize: 10, color: flagColor, fontWeight: FontWeight.bold)),
            ),
        ]),
        subtitle: Text(
          c.lastMsgPreview,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.unread > 0 ? Colors.black87 : Colors.grey.shade600,
            fontSize: 13,
            fontWeight: c.unread > 0 ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_formatTime(c.lastAt),
              style: TextStyle(
                fontSize: 11,
                color: c.unread > 0 ? const Color(0xFF2D5016) : Colors.grey,
                fontWeight: c.unread > 0 ? FontWeight.w600 : FontWeight.normal,
              )),
            if (c.unread > 0) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D5016),
                  borderRadius: BorderRadius.circular(10)),
                child: Text('${c.unread}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        onTap: () async {
          ApiService.markConversationRead(c.phone).catchError((_) {});
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(
              phone: c.phone,
              name: c.displayName,
              profilePicUrl: c.profilePicUrl,
            )));
          _load();
        },
        onLongPress: () => _showConvOptions(c, isArchived: isArchived),
      ),
    );
  }

  void _showConvOptions(Conversation c, {required bool isArchived}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              _buildAvatar(c),
              const SizedBox(width: 12),
              Text(c.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ),
          const Divider(),
          ListTile(
            leading: Icon(isArchived ? Icons.unarchive : Icons.archive, color: Colors.amber.shade700),
            title: Text(isArchived ? 'Restaurar conversación' : 'Archivar conversación'),
            onTap: () {
              Navigator.pop(context);
              _archive(c, archive: !isArchived);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Borrar conversación', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _delete(c);
            },
          ),
          const SizedBox(height: 8),
        ],
      )),
    );
  }

  List<Conversation> _filterConvs(List<Conversation> list) {
    if (_query.isEmpty) return list;
    return list.where((c) =>
      c.displayName.toLowerCase().contains(_query) ||
      c.phone.toLowerCase().contains(_query)
    ).toList();
  }

  Widget _searchBar() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    color: Colors.white,
    child: TextField(
      controller: _searchCtrl,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Buscar chats...',
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF2D5016), size: 20),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.close_rounded, color: Colors.grey.shade400, size: 18),
                onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); })
            : null,
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2D5016), width: 1.5)),
      ),
    ),
  );

  Widget _buildList(List<Conversation> convs, {bool archived = false}) {
    final alertCount = convs.where((c) => c.hasFlaggedMessages).length;
    return Column(children: [
      if (alertCount > 0 && !archived)
        Container(
          color: Colors.red.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('$alertCount conversación(es) requieren atención',
              style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
        ),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF2D5016)))
        : convs.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_query.isNotEmpty ? '🔍' : archived ? '📦' : '💬',
                style: const TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(_query.isNotEmpty ? 'Sin resultados'
                  : archived ? 'Sin conversaciones archivadas' : 'Sin conversaciones aún',
                style: const TextStyle(color: Colors.grey, fontSize: 15)),
            ]))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF2D5016),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: convs.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 72, endIndent: 16),
                itemBuilder: (_, i) => _buildConvTile(convs[i], isArchived: archived),
              ),
            )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final filteredChats    = _filterConvs(_chats);
    final filteredArchived = _filterConvs(_archived);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F4EE),
      body: Column(children: [
        Container(
          color: Colors.white,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TabBar(
              controller: _tabs,
              labelColor: const Color(0xFF2D5016),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF2D5016),
              tabs: [
                Tab(text: filteredChats.isNotEmpty ? 'Chats (${filteredChats.length})' : 'Chats'),
                Tab(text: filteredArchived.isNotEmpty ? 'Archivadas (${filteredArchived.length})' : 'Archivadas'),
              ],
            ),
            _searchBar(),
          ]),
        ),
        Expanded(child: TabBarView(
          controller: _tabs,
          children: [
            _buildList(filteredChats),
            _buildList(filteredArchived, archived: true),
          ],
        )),
      ]),
    );
  }
}
