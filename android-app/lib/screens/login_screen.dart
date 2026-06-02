import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  Future<void> _login() async {
    final user = _userCtrl.text.trim();
    final pin  = _pinCtrl.text;
    if (user.isEmpty || pin.isEmpty) {
      setState(() => _error = 'Ingresa usuario y PIN');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AppProvider>().login(user, pin);
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A3009),
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🌾', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 8),
          const Text('CONCENTRADOS MONSERRATH', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800,
            color: Color(0xFFD4800A), letterSpacing: 1.4)),
          const SizedBox(height: 6),
          const Text('Sistema de Pedidos', style: TextStyle(
            fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          const Text('Gestión WhatsApp', style: TextStyle(
            color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 36),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
              const Text('Iniciar sesión', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A3009))),
              const SizedBox(height: 20),
              TextField(
                controller: _userCtrl,
                decoration: InputDecoration(
                  labelText: 'Usuario',
                  hintText: 'Tu nombre de usuario',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                textInputAction: TextInputAction.next,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pinCtrl,
                obscureText: _obscure,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  hintText: '4 dígitos',
                  prefixIcon: const Icon(Icons.pin_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _loading ? null : _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _login,
                  icon: _loading
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.login_rounded),
                  label: Text(_loading ? 'Verificando...' : 'Ingresar',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2D5016),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ])),
          ),
        ]),
      ))),
    );
  }
}
