import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _pinCtrl  = TextEditingController();
  bool    _loading = false;
  bool    _obscure = true;
  String? _error;
  String  _serverUrl = ApiService.serverUrl;

  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
    _serverUrl = ApiService.serverUrl;
  }

  Future<void> _showServerDialog() async {
    final ctrl = TextEditingController(text: _serverUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.dns_rounded, color: Color(0xFF2D5016)),
          SizedBox(width: 8),
          Text('Servidor', style: TextStyle(fontSize: 18)),
        ]),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'URL del servidor',
            hintText: 'https://tu-dominio.duckdns.org',
            filled: true,
            fillColor: const Color(0xFFF6F6F6),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2D5016))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2D5016)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await ApiService.setServerUrl(result);
      if (mounted) setState(() => _serverUrl = result);
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _userCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final user = _userCtrl.text.trim();
    final pin  = _pinCtrl.text;
    if (user.isEmpty || pin.isEmpty) {
      setState(() => _error = 'Ingresa usuario y contraseña');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AppProvider>().login(user, pin);
    } catch (_) {
      HapticFeedback.lightImpact();
      setState(() => _error = 'Usuario o contraseña incorrectos');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F04),
      body: Stack(children: [
        // Decorative background blobs
        Positioned(top: -70, right: -70,
          child: _blob(220, const Color(0xFF2D5016), 0.35)),
        Positioned(top: 160, left: -50,
          child: _blob(150, const Color(0xFFD4800A), 0.08)),
        Positioned(bottom: -90, left: -50,
          child: _blob(300, const Color(0xFF1A3009), 0.6)),
        Positioned(bottom: 140, right: -30,
          child: _blob(100, const Color(0xFF2D5016), 0.2)),
        // Content
        SafeArea(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Column(children: [
                // Logo area
                Container(
                  width: 82, height: 82,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D5016),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFD4800A).withValues(alpha: 0.5), width: 2.5),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF2D5016).withValues(alpha: 0.5),
                        blurRadius: 24, spreadRadius: 2),
                    ],
                  ),
                  child: const Center(child: Text('🌾', style: TextStyle(fontSize: 38))),
                ),
                const SizedBox(height: 18),
                const Text('CONCENTRADOS MONSERRATH',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w900,
                    color: Color(0xFFD4800A), letterSpacing: 2.5)),
                const SizedBox(height: 6),
                const Text('Sistema de Pedidos',
                  style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                Text('Gestión WhatsApp',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
                const SizedBox(height: 42),

                // Login card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 32, offset: const Offset(0, 12)),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(26, 28, 26, 28),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Iniciar sesión',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800,
                          color: Color(0xFF1A3009))),
                      const SizedBox(height: 28),

                      _inputField(
                        controller: _userCtrl,
                        label: 'Usuario',
                        icon: Icons.person_outline_rounded,
                        action: TextInputAction.next,
                        autocorrect: false,
                        capitalize: TextCapitalization.none,
                      ),
                      const SizedBox(height: 14),
                      _inputField(
                        controller: _pinCtrl,
                        label: 'Contraseña',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscure,
                        onToggleObscure: () => setState(() => _obscure = !_obscure),
                        action: TextInputAction.done,
                        onSubmit: (_) { if (!_loading) _login(); },
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(children: [
                            Icon(Icons.error_outline_rounded,
                              color: Colors.red.shade600, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!,
                              style: TextStyle(
                                color: Colors.red.shade700, fontSize: 13))),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 24),

                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _loading ? null : _login,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2D5016),
                            disabledBackgroundColor: const Color(0xFF2D5016).withValues(alpha: 0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                          child: _loading
                            ? const SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.login_rounded, size: 20),
                                  SizedBox(width: 8),
                                  Text('Ingresar',
                                    style: TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5)),
                                ]),
                        ),
                      ),
                    ]),
                  ),
                ),

                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _showServerDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.dns_rounded, size: 13, color: Colors.white.withValues(alpha: 0.4)),
                      const SizedBox(width: 6),
                      Text(
                        _serverUrl.replaceFirst('https://', '').replaceFirst('http://', ''),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit_rounded, size: 11, color: Colors.white.withValues(alpha: 0.3)),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                Text('v2.0 — Monserrath © 2025',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 11)),
              ]),
            ),
          ),
        ))),
      ]),
    );
  }

  Widget _blob(double size, Color color, double opacity) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: opacity),
    ),
  );

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    TextInputAction action = TextInputAction.next,
    bool autocorrect = true,
    TextCapitalization capitalize = TextCapitalization.sentences,
    void Function(String)? onSubmit,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    autocorrect: autocorrect,
    textCapitalization: capitalize,
    textInputAction: action,
    onSubmitted: onSubmit,
    style: const TextStyle(fontSize: 15, color: Colors.black87),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF2D5016)),
      suffixIcon: onToggleObscure != null
        ? IconButton(
            icon: Icon(
              obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
              size: 20, color: Colors.grey.shade500),
            onPressed: onToggleObscure)
        : null,
      filled: true,
      fillColor: const Color(0xFFF6F6F6),
      labelStyle: const TextStyle(color: Colors.grey),
      floatingLabelStyle: const TextStyle(color: Color(0xFF2D5016)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF2D5016), width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    ),
  );
}
