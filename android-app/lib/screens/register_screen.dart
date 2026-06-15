import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey       = GlobalKey<FormState>();
  final _nameCtrl      = TextEditingController();
  final _usernameCtrl  = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _pwCtrl        = TextEditingController();
  final _pw2Ctrl       = TextEditingController();
  final _addressCtrl   = TextEditingController();
  final _nicknameCtrl  = TextEditingController();
  final _bioCtrl       = TextEditingController();

  bool    _loading = false;
  bool    _obscure1 = true;
  bool    _obscure2 = true;
  String? _error;

  static const _green     = Color(0xFF1A7A35);
  static const _greenDark = Color(0xFF0F4D20);
  static const _gold      = Color(0xFFD4800A);

  @override
  void dispose() {
    _nameCtrl.dispose(); _usernameCtrl.dispose(); _emailCtrl.dispose();
    _pwCtrl.dispose(); _pw2Ctrl.dispose(); _addressCtrl.dispose();
    _nicknameCtrl.dispose(); _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      // Create the account first
      await ApiService.register(
        username:    _usernameCtrl.text.trim(),
        password:    _pwCtrl.text,
        displayName: _nameCtrl.text.trim(),
        email:       _emailCtrl.text.trim(),
        address:     _addressCtrl.text.trim(),
        nickname:    _nicknameCtrl.text.trim().isEmpty ? null : _nicknameCtrl.text.trim(),
        bio:         _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
      );
      if (!mounted) return;
      // Auto-login with the new credentials
      await context.read<AppProvider>().login(
        _usernameCtrl.text.trim(), _pwCtrl.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool obscure = false,
    VoidCallback? onToggle,
    TextInputType keyboard = TextInputType.text,
    TextCapitalization capitalize = TextCapitalization.sentences,
    TextInputAction action = TextInputAction.next,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      textCapitalization: capitalize,
      textInputAction: action,
      maxLines: maxLines,
      validator: validator,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _green, size: 20),
        suffixIcon: onToggle != null
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20, color: Colors.grey.shade400),
                onPressed: onToggle)
            : null,
        filled: true,
        fillColor: const Color(0xFFF8FAF8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _green, width: 1.8)),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red)),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red, width: 1.8)),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _greenDark,
      appBar: AppBar(
        backgroundColor: _greenDark,
        foregroundColor: Colors.white,
        title: const Text('Crear cuenta',
          style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(children: [
            // Header strip
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('🌾', style: TextStyle(fontSize: 36)),
                const SizedBox(height: 8),
                const Text('Concentrados Monserrath',
                  style: TextStyle(color: _gold, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text('Regístrate para hacer pedidos',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
              ]),
            ),

            // Form card
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F0),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Información personal',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: Colors.black54, letterSpacing: 0.5)),
                  const SizedBox(height: 12),

                  _field(
                    controller: _nameCtrl,
                    label: 'Nombre completo *',
                    icon: Icons.badge_outlined,
                    capitalize: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Mínimo 2 caracteres' : null,
                  ),
                  const SizedBox(height: 12),

                  _field(
                    controller: _usernameCtrl,
                    label: 'Usuario *',
                    hint: 'Ej: maria123',
                    icon: Icons.person_outline_rounded,
                    capitalize: TextCapitalization.none,
                    keyboard: TextInputType.visiblePassword,
                    validator: (v) {
                      if (v == null || v.trim().length < 2) return 'Mínimo 2 caracteres';
                      if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(v.trim())) {
                        return 'Solo letras, números, . _ -';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  _field(
                    controller: _emailCtrl,
                    label: 'Correo electrónico *',
                    icon: Icons.email_outlined,
                    keyboard: TextInputType.emailAddress,
                    capitalize: TextCapitalization.none,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Campo requerido';
                      if (!RegExp(r'^[\w.+\-]+@[\w\-]+\.[a-z]{2,}$').hasMatch(v.trim())) {
                        return 'Correo inválido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  const Text('Contraseña',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: Colors.black54, letterSpacing: 0.5)),
                  const SizedBox(height: 12),

                  _field(
                    controller: _pwCtrl,
                    label: 'Contraseña *',
                    icon: Icons.lock_outline_rounded,
                    obscure: _obscure1,
                    onToggle: () => setState(() => _obscure1 = !_obscure1),
                    validator: (v) => (v == null || v.length < 8) ? 'Mínimo 8 caracteres' : null,
                  ),
                  const SizedBox(height: 12),

                  _field(
                    controller: _pw2Ctrl,
                    label: 'Confirmar contraseña *',
                    icon: Icons.lock_outline_rounded,
                    obscure: _obscure2,
                    onToggle: () => setState(() => _obscure2 = !_obscure2),
                    action: TextInputAction.next,
                    validator: (v) => v != _pwCtrl.text ? 'Las contraseñas no coinciden' : null,
                  ),
                  const SizedBox(height: 20),

                  const Text('Dirección de entrega',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: Colors.black54, letterSpacing: 0.5)),
                  const SizedBox(height: 12),

                  _field(
                    controller: _addressCtrl,
                    label: 'Dirección *',
                    hint: 'Ej: Calle 10 #5-30, Barrio El Prado',
                    icon: Icons.location_on_outlined,
                    maxLines: 2,
                    validator: (v) => (v == null || v.trim().length < 5) ? 'Mínimo 5 caracteres' : null,
                  ),
                  const SizedBox(height: 20),

                  const Text('Opcional',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: Colors.black54, letterSpacing: 0.5)),
                  const SizedBox(height: 12),

                  _field(
                    controller: _nicknameCtrl,
                    label: 'Apodo',
                    hint: 'Como quieres que te llamen',
                    icon: Icons.tag_rounded,
                    validator: null,
                  ),
                  const SizedBox(height: 12),

                  _field(
                    controller: _bioCtrl,
                    label: 'Descripción corta',
                    icon: Icons.notes_rounded,
                    maxLines: 2,
                    validator: null,
                  ),
                  const SizedBox(height: 20),

                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0F0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFCDD2)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFFD32F2F), size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!,
                          style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 13))),
                      ]),
                    ),

                  SizedBox(height: 54,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        disabledBackgroundColor: _green.withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _loading
                          ? const SizedBox(width: 24, height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.person_add_rounded, size: 20),
                              SizedBox(width: 10),
                              Text('Crear mi cuenta',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ]),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Center(child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('¿Ya tienes cuenta? Inicia sesión',
                      style: TextStyle(color: Color(0xFF1A7A35))),
                  )),
                  const SizedBox(height: 8),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
