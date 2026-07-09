import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key});
  @override State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  bool _loading = true;
  bool _saving  = false;

  // profile fields
  String _username    = '';
  String? _profilePic;
  final _nameCtrl     = TextEditingController();
  final _addressCtrl  = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _bioCtrl      = TextEditingController();

  // password change
  final _curPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _pw2Ctrl   = TextEditingController();
  bool _curObscure = true;
  bool _newObscure = true;
  bool _pw2Obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _addressCtrl.dispose();
    _nicknameCtrl.dispose(); _bioCtrl.dispose();
    _curPwCtrl.dispose(); _newPwCtrl.dispose(); _pw2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Reload profile info from the me endpoint via existing approach:
      // We'll use the stored displayName and call updateProfile with empty to get current data.
      // Actually, we'll use the saved info + let user edit it.
      _username = ApiService.currentUser;
      _nameCtrl.text = ApiService.displayName;
      // Other fields we'll try to load from a profile endpoint
      // For now, use what we have stored locally and allow editing
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      await ApiService.updateProfile({
        'display_name': _nameCtrl.text.trim(),
        'address':      _addressCtrl.text.trim(),
        'nickname':     _nicknameCtrl.text.trim(),
        'bio':          _bioCtrl.text.trim(),
      });
      if (mounted) _snack('Perfil actualizado', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    if (_newPwCtrl.text != _pw2Ctrl.text) {
      _snack('Las contraseñas no coinciden');
      return;
    }
    if (_newPwCtrl.text.length < 8) {
      _snack('La contraseña debe tener al menos 8 caracteres');
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService.changePassword(_curPwCtrl.text, _newPwCtrl.text);
      _curPwCtrl.clear(); _newPwCtrl.clear(); _pw2Ctrl.clear();
      if (mounted) _snack('Contraseña cambiada', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file   = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1280);
    if (file == null) return;
    setState(() => _saving = true);
    try {
      final bytes    = await file.readAsBytes();
      final filename = await ApiService.uploadProfilePic(file.path, bytes: bytes, mimeType: 'image/jpeg');
      if (mounted) setState(() => _profilePic = filename);
      if (mounted) _snack('Foto actualizada', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _saving = true);
    try {
      await ApiService.deleteProfilePic();
      if (mounted) setState(() => _profilePic = null);
      if (mounted) _snack('Foto eliminada', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Theme.of(context).colorScheme.primary : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  InputDecoration _deco(String label, IconData icon, {int? maxLines}) {
    final primary = Theme.of(context).colorScheme.primary;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: primary, size: 20),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.5)),
      alignLabelWithHint: maxLines != null && maxLines > 1,
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
    child: Text(title, style: const TextStyle(
      fontSize: 13, fontWeight: FontWeight.w700,
      color: Colors.black54, letterSpacing: 0.5)),
  );

  Widget _pwField(TextEditingController ctrl, String label, bool obscure, VoidCallback toggle) {
    final primary = Theme.of(context).colorScheme.primary;
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(Icons.lock_outline, color: primary, size: 20),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20, color: Colors.grey.shade400),
          onPressed: toggle),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 1.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: scheme.primary));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Avatar ─────────────────────────────────────────────
        Center(child: Column(children: [
          Stack(children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: scheme.primary.withValues(alpha: 0.1),
              backgroundImage: _profilePic != null
                ? NetworkImage(ApiService.profilePicUrl(_profilePic!)) : null,
              child: _profilePic == null
                ? Text(
                    ApiService.displayName.isNotEmpty
                      ? ApiService.displayName[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: scheme.primary, fontSize: 36, fontWeight: FontWeight.bold))
                : null,
            ),
            Positioned(bottom: 0, right: 0,
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: scheme.primary, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                ),
              )),
          ]),
          const SizedBox(height: 8),
          Text('@$_username',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          if (_profilePic != null) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _removePhoto,
              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
              label: const Text('Eliminar foto', style: TextStyle(color: Colors.red, fontSize: 12)),
            ),
          ],
        ])),

        const SizedBox(height: 24),

        // ── Perfil ─────────────────────────────────────────────
        _section('Información personal'),
        AppCard(
          child: Column(children: [
            TextField(
              controller: _nameCtrl,
              decoration: _deco('Nombre', Icons.badge_outlined),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              decoration: _deco('Dirección de entrega', Icons.location_on_outlined, maxLines: 2),
              maxLines: 2, minLines: 1,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nicknameCtrl,
              decoration: _deco('Apodo (opcional)', Icons.tag_rounded),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioCtrl,
              decoration: _deco('Descripción (opcional)', Icons.notes_rounded, maxLines: 2),
              maxLines: 2, minLines: 1,
            ),
          ]),
        ),

        const SizedBox(height: 12),
        AppButton(
          label: _saving ? 'Guardando...' : 'Guardar perfil',
          onPressed: _saving ? null : _saveProfile,
          loading: _saving,
          icon: Icons.save_rounded,
        ),

        const SizedBox(height: 24),

        // ── Contraseña ─────────────────────────────────────────
        _section('Cambiar contraseña'),
        AppCard(
          child: Column(children: [
            _pwField(_curPwCtrl, 'Contraseña actual', _curObscure,
              () => setState(() => _curObscure = !_curObscure)),
            const SizedBox(height: 12),
            _pwField(_newPwCtrl, 'Nueva contraseña (mín 8)', _newObscure,
              () => setState(() => _newObscure = !_newObscure)),
            const SizedBox(height: 12),
            _pwField(_pw2Ctrl, 'Confirmar contraseña', _pw2Obscure,
              () => setState(() => _pw2Obscure = !_pw2Obscure)),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _changePassword,
                icon: Icon(Icons.key_rounded, color: scheme.primary),
                label: Text('Cambiar contraseña',
                  style: TextStyle(color: scheme.primary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: scheme.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )),
          ]),
        ),

        const SizedBox(height: 24),

        // ── Notificaciones ─────────────────────────────────────
        _section('Preferencias'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              leading: Icon(Icons.notifications_outlined, color: scheme.primary),
              title: const Text('Notificaciones'),
              subtitle: const Text('Recibir alertas de pedidos'),
              trailing: Switch(
                value: true,
                onChanged: (_) {},
                activeColor: scheme.primary,
              ),
            ),
          ]),
        ),

        const SizedBox(height: 32),
      ]),
    );
  }
}
