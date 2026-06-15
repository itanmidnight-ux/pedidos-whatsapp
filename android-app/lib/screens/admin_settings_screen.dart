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

  final _nequiPhoneCtrl    = TextEditingController();
  final _nequiNameCtrl     = TextEditingController();
  final _empresaNombreCtrl = TextEditingController();
  final _empresaDescCtrl   = TextEditingController();
  final _horarioCtrl       = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nequiPhoneCtrl.dispose();
    _nequiNameCtrl.dispose();
    _empresaNombreCtrl.dispose();
    _empresaDescCtrl.dispose();
    _horarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await ApiService.getSettings();
      if (mounted) {
        _nequiPhoneCtrl.text    = s['nequi_phone']        ?? '';
        _nequiNameCtrl.text     = s['nequi_name']         ?? '';
        _empresaNombreCtrl.text = s['empresa_nombre']     ?? '';
        _empresaDescCtrl.text   = s['empresa_descripcion'] ?? '';
        _horarioCtrl.text       = s['horario_atencion']   ?? '';
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Future.wait([
        ApiService.updateSetting('nequi_phone',        _nequiPhoneCtrl.text.trim()),
        ApiService.updateSetting('nequi_name',         _nequiNameCtrl.text.trim()),
        ApiService.updateSetting('empresa_nombre',     _empresaNombreCtrl.text.trim()),
        ApiService.updateSetting('empresa_descripcion', _empresaDescCtrl.text.trim()),
        ApiService.updateSetting('horario_atencion',   _horarioCtrl.text.trim()),
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

  InputDecoration _deco(String label, IconData icon, {int? maxLines}) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: _green, size: 20),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _green, width: 1.5),
    ),
    alignLabelWithHint: maxLines != null && maxLines > 1,
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(title, style: const TextStyle(
      fontSize: 16, fontWeight: FontWeight.bold, color: _green)),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _green));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Empresa section
        _sectionTitle('Información de la empresa'),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              TextField(
                controller: _empresaNombreCtrl,
                decoration: _deco('Nombre de la empresa', Icons.business_outlined),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _empresaDescCtrl,
                decoration: _deco('Descripción', Icons.description_outlined, maxLines: 3),
                maxLines: 3,
                minLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _horarioCtrl,
                decoration: _deco('Horario de atención', Icons.access_time_outlined),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Ej: Lunes a Sábado 8:00am - 6:00pm',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            ]),
          ),
        ),

        const SizedBox(height: 24),

        // Nequi section
        _sectionTitle('Pago Nequi'),
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
                  'Los clientes verán este número para transferencias.',
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
            style: FilledButton.styleFrom(backgroundColor: _green),
            icon: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Guardando...' : 'Guardar configuración'),
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}
