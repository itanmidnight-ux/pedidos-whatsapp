import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_button.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _pinCtrl  = TextEditingController();
  final _formKey  = GlobalKey<FormState>();

  bool    _loading  = false;
  bool    _obscure  = true;
  bool    _remember = true;
  String? _error;
  String  _serverUrl = ApiService.serverUrl;

  // animations
  late final AnimationController _enterCtrl;
  late final AnimationController _shakeCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;
  late final Animation<double>   _shakeAnim;

  // logo tap counter for server config (admin hidden feature)
  int _logoTaps = 0;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

    _fadeAnim  = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -8),  weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8),   weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: 0),    weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));

    _enterCtrl.forward();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final savedUsername = await ApiService.loadCredentials();
    if (savedUsername.isNotEmpty && mounted) {
      setState(() {
        _userCtrl.text = savedUsername;
        _remember = true;
      });
    }
    _serverUrl = ApiService.serverUrl;
    if (mounted) setState(() {});
  }

  Future<void> _showServerDialog() async {
    final primary = Theme.of(context).colorScheme.primary;
    final ctrl = TextEditingController(text: _serverUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(Icons.dns_rounded, color: primary),
          const SizedBox(width: 8),
          const Text('Configuración', style: TextStyle(fontSize: 18)),
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
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primary)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: primary),
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

  void _onLogoTap() {
    _logoTaps++;
    if (_logoTaps >= 5) {
      _logoTaps = 0;
      _showServerDialog();
    }
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _shakeCtrl.dispose();
    _userCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final user = _userCtrl.text.trim();
    final pin  = _pinCtrl.text;
    if (user.isEmpty || pin.isEmpty) {
      setState(() => _error = 'Completa todos los campos para continuar');
      _shakeCtrl.forward(from: 0);
      HapticFeedback.lightImpact();
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AppProvider>().login(user, pin);
      if (context.mounted) await context.read<ThemeProvider>().load();
      if (_remember) {
        await ApiService.saveCredentials(user);
      } else {
        await ApiService.clearCredentials();
      }
    } catch (_) {
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() => _error = 'Credenciales incorrectas. Intenta de nuevo.');
        _shakeCtrl.forward(from: 0);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final scheme = Theme.of(context).colorScheme;
    final headerH = (h * 0.26).clamp(140.0, 200.0);
    return Scaffold(
      backgroundColor: scheme.primary,
      body: Stack(children: [
        // Background pattern
        Positioned.fill(child: CustomPaint(painter: _BgPainter())),

        // Top decorative wave / banner
        Positioned(
          top: 0, left: 0, right: 0,
          child: SizedBox(
            height: headerH,
            child: Stack(alignment: Alignment.center, children: [
              // Wave
              Positioned.fill(
                child: ClipPath(
                  clipper: _WaveClipper(),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, 0.35)!],
                      ),
                    ),
                  ),
                ),
              ),
              // Logo & brand
              FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: MediaQuery.of(context).padding.top + 8),
                    GestureDetector(
                      onTap: _onLogoTap,
                      child: Container(
                        width: 66, height: 66,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.12),
                          border: Border.all(
                            color: scheme.secondary.withValues(alpha: 0.7), width: 2.5),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 20, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: const Center(child: Text('🌾', style: TextStyle(fontSize: 30))),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('CONCENTRADOS MONSERRATH',
                      style: TextStyle(
                        color: scheme.secondary, fontSize: 11, fontWeight: FontWeight.w900,
                        letterSpacing: 2.5)),
                    const SizedBox(height: 4),
                    const Text('Tu pedido, nuestra prioridad',
                      style: TextStyle(
                        color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w400,
                        letterSpacing: 0.3)),
                  ],
                ),
              ),
            ]),
          ),
        ),

        // Main scrollable content
        SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(children: [
                  SizedBox(height: headerH - 30),

                  // Login card
                  AnimatedBuilder(
                    animation: _shakeAnim,
                    builder: (_, child) => Transform.translate(
                      offset: Offset(_shakeAnim.value, 0),
                      child: child,
                    ),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 40, offset: const Offset(0, 16)),
                          BoxShadow(color: scheme.primary.withValues(alpha: 0.08),
                            blurRadius: 20, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                        child: Form(
                          key: _formKey,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            // Welcome header
                            Row(children: [
                              Container(
                                width: 38, height: 38,
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.storefront_rounded, color: scheme.primary, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('¡Bienvenido!',
                                  style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A1A1A))),
                                Text('Ingresa para ver y pedir productos',
                                  style: TextStyle(
                                    fontSize: 11, color: Colors.black45)),
                              ]),
                            ]),
                            const SizedBox(height: 16),

                            // Username
                            _buildField(
                              controller: _userCtrl,
                              label: 'Tu usuario',
                              hint: 'Ej: maria123',
                              icon: Icons.person_outline_rounded,
                              action: TextInputAction.next,
                              autocorrect: false,
                              capitalize: TextCapitalization.none,
                            ),
                            const SizedBox(height: 10),

                            // Password
                            _buildField(
                              controller: _pinCtrl,
                              label: 'Contraseña',
                              hint: '••••••••',
                              icon: Icons.lock_outline_rounded,
                              obscure: _obscure,
                              onToggle: () => setState(() => _obscure = !_obscure),
                              action: TextInputAction.done,
                              onSubmit: (_) { if (!_loading) _login(); },
                            ),
                            const SizedBox(height: 8),

                            // Remember me
                            Row(children: [
                              SizedBox(
                                width: 20, height: 20,
                                child: Checkbox(
                                  value: _remember,
                                  onChanged: (v) => setState(() => _remember = v ?? true),
                                  activeColor: scheme.primary,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Recordar mi usuario',
                                style: TextStyle(fontSize: 13, color: Colors.black54)),
                            ]),

                            // Error message
                            AnimatedSize(
                              duration: const Duration(milliseconds: 250),
                              child: _error != null
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF0F0),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFFFFCDD2)),
                                      ),
                                      child: Row(children: [
                                        const Icon(Icons.info_outline_rounded,
                                          color: Color(0xFFD32F2F), size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(_error!,
                                          style: const TextStyle(
                                            color: Color(0xFFD32F2F), fontSize: 13))),
                                      ]),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 14),

                            // Login button
                            AppButton(
                              label: 'Ingresar',
                              onPressed: _loading ? null : _login,
                              loading: _loading,
                              icon: Icons.shopping_basket_rounded,
                            ),

                            const SizedBox(height: 10),
                            // Register button
                            SizedBox(height: 48,
                              child: OutlinedButton(
                                onPressed: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => const RegisterScreen())),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.person_add_outlined, size: 18, color: scheme.primary),
                                    const SizedBox(width: 8),
                                    Text('¿Sin cuenta? Regístrate',
                                      style: TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w600,
                                        color: scheme.primary)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(child: Divider(color: Colors.grey.shade200)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('¿Problemas?',
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                              ),
                              Expanded(child: Divider(color: Colors.grey.shade200)),
                            ]),
                            const SizedBox(height: 4),
                            Center(child: TextButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Contacta a Concentrados Monserrath para recuperar tu acceso'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.support_agent_rounded, size: 16, color: Colors.grey),
                              label: const Text('Contactar soporte',
                                style: TextStyle(color: Colors.grey, fontSize: 12)),
                            )),
                          ]),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  // Security badges
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SecurityBadge(icon: Icons.lock_rounded, label: 'Conexión segura'),
                      const SizedBox(width: 16),
                      _SecurityBadge(icon: Icons.verified_user_rounded, label: 'Datos protegidos'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('v2.0 — Monserrath © 2025',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 10)),
                  const SizedBox(height: 10),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    VoidCallback? onToggle,
    TextInputAction action = TextInputAction.next,
    bool autocorrect = true,
    TextCapitalization capitalize = TextCapitalization.sentences,
    void Function(String)? onSubmit,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: autocorrect,
      textCapitalization: capitalize,
      textInputAction: action,
      onSubmitted: onSubmit,
      style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade300, fontSize: 14),
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Icon(icon, size: 20, color: primary),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 50),
        suffixIcon: onToggle != null
          ? IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20, color: Colors.grey.shade400),
              onPressed: onToggle)
          : null,
        filled: true,
        fillColor: const Color(0xFFF8FAF8),
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        floatingLabelStyle: TextStyle(color: primary, fontSize: 13, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 1.8)),
        contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
      ),
    );
  }
}

// ── Background painter ─────────────────────────────────────────
class _BgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    // subtle grid dots pattern
    paint.color = Colors.white.withValues(alpha: 0.025);
    for (double x = 0; x < size.width; x += 28) {
      for (double y = 0; y < size.height; y += 28) {
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }
  @override bool shouldRepaint(_) => false;
}

// ── Wave clipper ───────────────────────────────────────────────
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..lineTo(0, size.height - 40)
      ..quadraticBezierTo(
          size.width * 0.25, size.height + 20,
          size.width * 0.5,  size.height - 10)
      ..quadraticBezierTo(
          size.width * 0.75, size.height - 40,
          size.width,        size.height - 10)
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }
  @override bool shouldReclip(_) => false;
}

// ── Security badge widget ──────────────────────────────────────
class _SecurityBadge extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _SecurityBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.4)),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
  ]);
}
