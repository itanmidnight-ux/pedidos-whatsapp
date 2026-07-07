import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_button.dart';
import '../widgets/empty_state.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> with SingleTickerProviderStateMixin {
  bool _loading = false;
  late final TabController _tabs;
  final _staffSearchCtrl  = TextEditingController();
  final _clientSearchCtrl = TextEditingController();
  String _staffQuery  = '';
  String _clientQuery = '';
  List<Map<String, dynamic>> _clients = [];
  bool _loadingClients = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _staffSearchCtrl.addListener(
      () => setState(() => _staffQuery = _staffSearchCtrl.text.toLowerCase()));
    _clientSearchCtrl.addListener(
      () => setState(() => _clientQuery = _clientSearchCtrl.text.toLowerCase()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().refreshUsers();
      _loadClients();
    });
    _tabs.addListener(() { if (_tabs.indexIsChanging && _tabs.index == 1) _loadClients(); });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _staffSearchCtrl.dispose();
    _clientSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    setState(() => _loadingClients = true);
    try {
      final c = await ApiService.getClients();
      if (mounted) setState(() => _clients = c);
    } catch (_) {}
    if (mounted) setState(() => _loadingClients = false);
  }

  // ── Dialogo crear / editar personal (admin/worker) ─────────
  Future<void> _showStaffDialog({Map<String, dynamic>? user}) async {
    final isEdit = user != null;
    final displayCtrl  = TextEditingController(text: isEdit ? user['display_name'] ?? '' : '');
    final usernameCtrl = TextEditingController(text: isEdit ? user['username'] ?? '' : '');
    final pwCtrl       = TextEditingController();
    final addressCtrl  = TextEditingController(text: isEdit ? user['address'] ?? '' : '');
    bool  pwObscure    = true;
    String role = isEdit ? (user['role'] ?? 'worker') : 'worker';
    bool   active = isEdit ? (user['active'] == 1 || user['active'] == true) : true;
    final formKey = GlobalKey<FormState>();
    final scheme = Theme.of(context).colorScheme;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (ctx, setS) => Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                )),
                const SizedBox(height: 16),
                Text(
                  isEdit ? 'Editar usuario' : 'Nuevo usuario',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.primary),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: displayCtrl,
                  decoration: _inputDeco('Nombre visible', Icons.badge_outlined),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: usernameCtrl,
                  decoration: _inputDeco('Usuario (login)', Icons.person_outline),
                  readOnly: isEdit,
                  style: isEdit ? TextStyle(color: Colors.grey.shade500) : null,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
                ),
                const SizedBox(height: 12),
                StatefulBuilder(builder: (_, setPw) => TextFormField(
                  controller: pwCtrl,
                  obscureText: pwObscure,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: isEdit ? 'Contraseña (vacío = sin cambio)' : 'Contraseña',
                    prefixIcon: Icon(Icons.lock_outline, size: 20, color: scheme.primary),
                    suffixIcon: IconButton(
                      icon: Icon(pwObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                      onPressed: () => setPw(() => pwObscure = !pwObscure),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: scheme.primary, width: 1.5)),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.red)),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.red, width: 1.5)),
                  ),
                  validator: (v) {
                    if (!isEdit && (v == null || v.trim().isEmpty)) return 'Contraseña requerida';
                    return null;
                  },
                )),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role == 'client' ? 'worker' : role,
                  decoration: _inputDeco('Rol', Icons.admin_panel_settings_outlined),
                  items: const [
                    DropdownMenuItem(value: 'worker', child: Text('Trabajador')),
                    DropdownMenuItem(value: 'admin',  child: Text('Administrador')),
                  ],
                  onChanged: (v) { if (v != null) setS(() => role = v); },
                ),
                const SizedBox(height: 12),
                if (isEdit)
                  SwitchListTile(
                    value: active,
                    onChanged: (v) => setS(() => active = v),
                    title: const Text('Usuario activo'),
                    activeThumbColor: scheme.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: AppButton(
                    label: isEdit ? 'Guardar' : 'Crear',
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(ctx);
                      setState(() => _loading = true);
                      try {
                        final prov = context.read<AppProvider>();
                        if (isEdit) {
                          final data = <String, dynamic>{
                            'display_name': displayCtrl.text.trim(),
                            'role':         role,
                            'active':       active ? 1 : 0,
                            'address':      addressCtrl.text.trim(),
                          };
                          if (pwCtrl.text.trim().isNotEmpty) data['password'] = pwCtrl.text.trim();
                          await prov.updateUser(user['id'] as int, data);
                        } else {
                          await prov.createUser(
                            usernameCtrl.text.trim(),
                            pwCtrl.text.trim(),
                            displayCtrl.text.trim(),
                            role: role,
                          );
                        }
                        if (mounted) _snack(isEdit ? 'Usuario actualizado' : 'Usuario creado', success: true);
                      } catch (e) {
                        if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
                      } finally {
                        if (mounted) setState(() => _loading = false);
                      }
                    },
                  )),
                ]),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> user) async {
    final newActive = !(user['active'] == 1 || user['active'] == true);
    final name = user['display_name'] ?? user['username'];
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(newActive ? 'Activar usuario' : 'Desactivar usuario'),
        content: Text(newActive
          ? '¿Activar acceso para $name?'
          : '¿Desactivar acceso para $name? No podrá iniciar sesión.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: newActive ? scheme.primary : Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(newActive ? 'Activar' : 'Desactivar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await context.read<AppProvider>().updateUser(
        user['id'] as int, {'active': newActive ? 1 : 0});
      if (mounted) _snack(newActive ? '$name activado' : '$name desactivado', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user, {bool isClient = false}) async {
    final name = user['display_name'] ?? user['username'];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Eliminar permanentemente a $name?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ApiService.deleteUser(user['id'] as int);
      if (isClient) {
        await _loadClients();
      } else {
        await context.read<AppProvider>().refreshUsers();
      }
      if (mounted) _snack('$name eliminado', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool success = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? scheme.primary : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: scheme.primary),
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }

  Widget _searchBar(TextEditingController ctrl, String query, String hint) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      color: Colors.white,
      child: TextField(
        controller: ctrl,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: scheme.primary, size: 20),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded, color: Colors.grey.shade400, size: 18),
                  onPressed: () { ctrl.clear(); })
              : null,
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.primary, width: 1.5)),
        ),
      ),
    );
  }

  Widget _userTile(Map<String, dynamic> u, {bool isClient = false}) {
    final scheme  = Theme.of(context).colorScheme;
    final name    = u['display_name'] ?? u['username'] ?? '?';
    final uname   = u['username'] ?? '';
    final role    = u['role'] ?? 'worker';
    final active  = u['active'] == 1 || u['active'] == true;
    final isAdmin = role == 'admin';
    final badgeColor  = isAdmin ? scheme.secondary : isClient ? Colors.blue : scheme.primary;
    final badgeText   = isAdmin ? 'Admin' : isClient ? 'Cliente' : 'Trabajador';
    final avatarColor = isAdmin
        ? scheme.secondary.withValues(alpha: active ? 1 : 0.4)
        : isClient
            ? Colors.blue.withValues(alpha: active ? 0.8 : 0.3)
            : scheme.primary.withValues(alpha: active ? 1 : 0.35);

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: active ? Colors.transparent : Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: avatarColor,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          title: Row(children: [
            Expanded(child: Text(
              name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: active ? Colors.black87 : Colors.grey),
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20)),
              child: Text(badgeText,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: badgeColor)),
            ),
          ]),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('@$uname', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            if (u['email'] != null && (u['email'] as String).isNotEmpty)
              Text(u['email'] as String,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
            if (!active)
              const Text('INACTIVO',
                style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
          ]),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!isClient)
              IconButton(
                icon: Icon(
                  active ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                  color: active ? scheme.primary : Colors.grey, size: 28),
                tooltip: active ? 'Desactivar' : 'Activar',
                onPressed: () => _toggleActive(u),
              ),
            if (!isClient)
              IconButton(
                icon: Icon(Icons.edit_rounded, size: 20, color: scheme.primary),
                onPressed: () => _showStaffDialog(user: u),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
              onPressed: () => _deleteUser(u, isClient: isClient),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allUsers = context.watch<AppProvider>().users;
    final staff = allUsers.where((u) => u['role'] != 'client').where((u) {
      if (_staffQuery.isEmpty) return true;
      final n  = (u['display_name'] ?? '').toString().toLowerCase();
      final un = (u['username'] ?? '').toString().toLowerCase();
      return n.contains(_staffQuery) || un.contains(_staffQuery);
    }).toList();

    final clients = _clientQuery.isEmpty ? _clients : _clients.where((u) {
      final n  = (u['display_name'] ?? '').toString().toLowerCase();
      final un = (u['username'] ?? '').toString().toLowerCase();
      final e  = (u['email'] ?? '').toString().toLowerCase();
      return n.contains(_clientQuery) || un.contains(_clientQuery) || e.contains(_clientQuery);
    }).toList();

    return Column(children: [
      Container(
        color: Colors.white,
        child: TabBar(
          controller: _tabs,
          labelColor: scheme.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: scheme.primary,
          tabs: [
            Tab(text: 'Personal (${staff.length})'),
            Tab(text: 'Clientes (${clients.length})'),
          ],
        ),
      ),
      Expanded(child: Stack(children: [
        TabBarView(
          controller: _tabs,
          children: [
            // ── Tab 1: Admins + Workers ──────────────────────
            Column(children: [
              _searchBar(_staffSearchCtrl, _staffQuery, 'Buscar personal...'),
              Expanded(child: RefreshIndicator(
                onRefresh: () => context.read<AppProvider>().refreshUsers(),
                color: scheme.primary,
                child: staff.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 100),
                        EmptyState(
                          icon: _staffQuery.isNotEmpty ? Icons.search_off_rounded : Icons.people_outline_rounded,
                          title: _staffQuery.isNotEmpty ? 'Sin resultados' : 'No hay personal',
                        ),
                      ])
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                        children: staff.map((u) => _userTile(u)).toList(),
                      ),
              )),
            ]),

            // ── Tab 2: Clients ───────────────────────────────
            Column(children: [
              _searchBar(_clientSearchCtrl, _clientQuery, 'Buscar clientes...'),
              Expanded(child: RefreshIndicator(
                onRefresh: _loadClients,
                color: scheme.primary,
                child: _loadingClients
                    ? Center(child: CircularProgressIndicator(color: scheme.primary))
                    : clients.isEmpty
                        ? ListView(children: [
                            const SizedBox(height: 100),
                            EmptyState(
                              icon: _clientQuery.isNotEmpty ? Icons.search_off_rounded : Icons.shopping_cart_outlined,
                              title: _clientQuery.isNotEmpty ? 'Sin resultados' : 'No hay clientes registrados',
                              subtitle: _clientQuery.isEmpty ? 'Los clientes se registran desde la app' : null,
                            ),
                          ])
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                            children: clients.map((u) => _userTile(u, isClient: true)).toList(),
                          ),
              )),
            ]),
          ],
        ),

        // Loading overlay
        if (_loading)
          Positioned.fill(child: ColoredBox(
            color: Colors.black12,
            child: Center(child: CircularProgressIndicator(color: scheme.primary)),
          )),

        // FAB only on Tab 0 (staff)
        AnimatedBuilder(
          animation: _tabs,
          builder: (_, __) => _tabs.index == 0
              ? Positioned(
                  bottom: 20, right: 16,
                  child: FloatingActionButton.extended(
                    onPressed: () => _showStaffDialog(),
                    backgroundColor: scheme.primary,
                    icon: const Icon(Icons.person_add_rounded, color: Colors.white),
                    label: const Text('Nuevo usuario',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ])),
    ]);
  }
}
