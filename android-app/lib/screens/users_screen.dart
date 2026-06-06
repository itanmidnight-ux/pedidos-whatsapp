import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import '../widgets/company_header.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  static const _green  = Color(0xFF2D5016);
  static const _gold   = Color(0xFFD4800A);
  static const _bg     = Color(0xFFF8F4EE);
  static const _light  = Color(0xFFD4ECB8);

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().refreshUsers();
    });
  }

  // ── Dialogo crear / editar ─────────────────────────────────
  Future<void> _showUserDialog({Map<String, dynamic>? user}) async {
    final isEdit = user != null;
    final displayCtrl  = TextEditingController(text: isEdit ? user['display_name'] ?? '' : '');
    final usernameCtrl = TextEditingController(text: isEdit ? user['username'] ?? '' : '');
    final pinCtrl      = TextEditingController();
    String role = isEdit ? (user['role'] ?? 'worker') : 'worker';
    bool   active = isEdit ? (user['active'] == 1 || user['active'] == true) : true;
    final formKey = GlobalKey<FormState>();

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
                // Handle bar
                Center(child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
                const SizedBox(height: 16),
                Text(
                  isEdit ? 'Editar usuario' : 'Nuevo usuario',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _green),
                ),
                const SizedBox(height: 20),

                // Display name
                TextFormField(
                  controller: displayCtrl,
                  decoration: _inputDeco('Nombre visible', Icons.badge_outlined),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
                ),
                const SizedBox(height: 12),

                // Username
                TextFormField(
                  controller: usernameCtrl,
                  decoration: _inputDeco('Usuario (login)', Icons.person_outline),
                  readOnly: isEdit,
                  style: isEdit ? TextStyle(color: Colors.grey.shade500) : null,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
                ),
                const SizedBox(height: 12),

                // PIN
                TextFormField(
                  controller: pinCtrl,
                  decoration: _inputDeco(
                    isEdit ? 'PIN (dejar vacío para no cambiar)' : 'PIN (4 dígitos)',
                    Icons.lock_outline,
                  ),
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  validator: (v) {
                    if (!isEdit && (v == null || v.trim().length < 4)) return 'PIN de 4 dígitos requerido';
                    if (v != null && v.isNotEmpty && v.trim().length < 4) return 'PIN debe tener 4 dígitos';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Rol
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: _inputDeco('Rol', Icons.admin_panel_settings_outlined),
                  items: const [
                    DropdownMenuItem(value: 'worker', child: Text('Trabajador')),
                    DropdownMenuItem(value: 'admin',  child: Text('Administrador')),
                    DropdownMenuItem(value: 'client', child: Text('Cliente')),
                  ],
                  onChanged: (v) { if (v != null) setS(() => role = v); },
                ),
                const SizedBox(height: 12),

                // Activo (solo en edición)
                if (isEdit)
                  SwitchListTile(
                    value: active,
                    onChanged: (v) => setS(() => active = v),
                    title: const Text('Usuario activo'),
                    activeColor: _green,
                    contentPadding: EdgeInsets.zero,
                  ),

                const SizedBox(height: 20),

                // Botones
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _green),
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
                          };
                          if (pinCtrl.text.trim().isNotEmpty) data['pin'] = pinCtrl.text.trim();
                          await prov.updateUser(user['id'] as int, data);
                        } else {
                          await prov.createUser(
                            usernameCtrl.text.trim(),
                            pinCtrl.text.trim(),
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
                    child: Text(isEdit ? 'Guardar' : 'Crear'),
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

  // ── Toggle activo rápido ───────────────────────────────────
  Future<void> _toggleActive(Map<String, dynamic> user) async {
    final newActive = !(user['active'] == 1 || user['active'] == true);
    final name = user['display_name'] ?? user['username'];
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
            style: FilledButton.styleFrom(backgroundColor: newActive ? _green : Colors.red),
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
        user['id'] as int,
        {'active': newActive ? 1 : 0},
      );
      if (mounted) _snack(newActive ? '$name activado' : '$name desactivado', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final name = user['display_name'] ?? user['username'];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Eliminar permanentemente a $name? Esta acción no se puede deshacer.'),
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
      await context.read<AppProvider>().refreshUsers();
      if (mounted) _snack('$name eliminado', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? _green : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20, color: _green),
    filled: true,
    fillColor: const Color(0xFFF5F5F5),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _green, width: 1.5),
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

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final users = context.watch<AppProvider>().users;

    return Stack(children: [
      RefreshIndicator(
        onRefresh: () => context.read<AppProvider>().refreshUsers(),
        color: _green,
        child: users.isEmpty
          ? ListView(children: [
              const SizedBox(height: 120),
              Column(children: [
                const Text('👥', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(_loading ? 'Cargando...' : 'No hay usuarios',
                  style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                const Text('Desliza para actualizar', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final u    = users[i];
                final name = u['display_name'] ?? u['username'] ?? '?';
                final uname = u['username'] ?? '';
                final role  = u['role'] ?? 'worker';
                final active = u['active'] == 1 || u['active'] == true;
                final isAdminUser  = role == 'admin';
                final isClientUser = role == 'client';
                final badgeColor = isAdminUser ? _gold : isClientUser ? Colors.blue : _green;
                final badgeText  = isAdminUser ? 'Admin' : isClientUser ? 'Cliente' : 'Trabajador';
                final avatarColor = isAdminUser
                    ? _gold.withOpacity(active ? 1 : 0.4)
                    : isClientUser
                        ? Colors.blue.withOpacity(active ? 0.8 : 0.3)
                        : _green.withOpacity(active ? 1 : 0.35);

                return Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: active ? Colors.transparent : Colors.grey.shade200,
                    ),
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
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: active ? Colors.black87 : Colors.grey,
                          ),
                        )),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: badgeColor,
                            ),
                          ),
                        ),
                      ]),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('@$uname', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                          if (!active)
                            const Text('INACTIVO',
                              style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isClientUser)
                            IconButton(
                              icon: Icon(
                                active ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                                color: active ? _green : Colors.grey,
                                size: 28,
                              ),
                              tooltip: active ? 'Desactivar' : 'Activar',
                              onPressed: () => _toggleActive(u),
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, size: 20, color: Color(0xFF2D5016)),
                            tooltip: 'Editar',
                            onPressed: () => _showUserDialog(user: u),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
                            tooltip: 'Eliminar',
                            onPressed: () => _deleteUser(u),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      ),

      // Loading overlay
      if (_loading)
        const Positioned.fill(child: ColoredBox(
          color: Colors.black12,
          child: Center(child: CircularProgressIndicator(color: _green)),
        )),

      // FAB
      Positioned(
        bottom: 20,
        right: 16,
        child: FloatingActionButton.extended(
          onPressed: () => _showUserDialog(),
          backgroundColor: _green,
          icon: const Icon(Icons.person_add_rounded, color: Colors.white),
          label: const Text('Nuevo usuario', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }
}
