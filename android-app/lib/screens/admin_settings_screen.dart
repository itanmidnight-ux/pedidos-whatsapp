import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});
  @override State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  static const _green = Color(0xFF1E6B2E);
  bool _loading = true;
  bool _saving   = false;

  final _nequiPhoneCtrl = TextEditingController();
  final _nequiNameCtrl  = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nequiPhoneCtrl.dispose();
    _nequiNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await ApiService.getSettings();
      if (mounted) {
        _nequiPhoneCtrl.text = s['nequi_phone'] ?? '';
        _nequiNameCtrl.text  = s['nequi_name']  ?? '';
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Future.wait([
        ApiService.updateSetting('nequi_phone', _nequiPhoneCtrl.text.trim()),
        ApiService.updateSetting('nequi_name',  _nequiNameCtrl.text.trim()),
      ]);
      if (mounted) _snack('Configuración guardada', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? _green : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: _green, size: 20),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _green, width: 1.5),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _green));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Nequi section
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Pago Nequi', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: _green)),
        ),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              TextField(
                controller: _nequiPhoneCtrl,
                decoration: _deco('Número Nequi', Icons.phone_outlined),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nequiNameCtrl,
                decoration: _deco('Nombre en Nequi', Icons.person_outline),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Los clientes verán este número para realizar transferencias Nequi.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            ]),
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Guardando...' : 'Guardar configuración'),
          ),
        ),
      ]),
    );
  }
}
