import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});
  @override State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  static const _presets = [
    {'name': 'Olivo & Ámbar',      'primary': '#2D5016', 'accent': '#D4800A'},
    {'name': 'Bosque & Cuero',      'primary': '#1B4332', 'accent': '#B08968'},
    {'name': 'Slate & Terracota',   'primary': '#264653', 'accent': '#E76F51'},
    {'name': 'Vino & Oro',          'primary': '#5C1A28', 'accent': '#C9A227'},
    {'name': 'Azul Corporativo',    'primary': '#1B3A6B', 'accent': '#3D8BFD'},
    {'name': 'Carbón & Lima',       'primary': '#22302B', 'accent': '#8AB833'},
  ];
  String _selectedPrimary = '#2D5016';
  String _selectedAccent  = '#D4800A';
  bool _savingBrand = false;

  bool _loading = true;
  bool _saving   = false;

  final _nequiPhoneCtrl    = TextEditingController();
  final _nequiNameCtrl     = TextEditingController();
  final _empresaNombreCtrl = TextEditingController();
  final _empresaDescCtrl   = TextEditingController();
  final _horarioCtrl       = TextEditingController();

  Map<String, dynamic>? _botStatus;
  bool _restartingBot = false;
  Timer? _botTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBotStatus();
    _botTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadBotStatus());
  }

  @override
  void dispose() {
    _nequiPhoneCtrl.dispose();
    _nequiNameCtrl.dispose();
    _empresaNombreCtrl.dispose();
    _empresaDescCtrl.dispose();
    _horarioCtrl.dispose();
    _botTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBotStatus() async {
    try {
      final s = await ApiService.getBotStatus();
      if (mounted) setState(() => _botStatus = s);
    } catch (_) {}
  }

  Future<void> _restartBot() async {
    setState(() => _restartingBot = true);
    try {
      await ApiService.restartBot();
      if (mounted) _snack('Bot reiniciando...', success: true);
      await Future.delayed(const Duration(seconds: 2));
      await _loadBotStatus();
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _restartingBot = false);
    }
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

  Future<void> _saveBranding() async {
    setState(() => _savingBrand = true);
    try {
      await ApiService.updateSetting('theme_primary', _selectedPrimary);
      await ApiService.updateSetting('theme_accent', _selectedAccent);
      if (mounted) await context.read<ThemeProvider>().reload();
      if (mounted) _snack('Marca actualizada', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingBrand = false);
    }
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512);
    if (file == null) return;
    try {
      await ApiService.uploadLogo(file.path);
      if (mounted) await context.read<ThemeProvider>().reload();
      if (mounted) _snack('Logo actualizado', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
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
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
      alignLabelWithHint: maxLines != null && maxLines > 1,
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(title, style: TextStyle(
      fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
  );

  String _timeAgo(String? iso) {
    if (iso == null) return 'nunca';
    final t = DateTime.tryParse(iso);
    if (t == null) return 'nunca';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1)  return 'hace instantes';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24)   return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} días';
  }

  Widget _statRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(icon, size: 18, color: Colors.grey.shade600),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _botStatusCard() {
    final s = _botStatus;
    final primary = Theme.of(context).colorScheme.primary;
    final ready = s?['ready'] == true;
    final exhausted = s?['reconnectExhausted'] == true;
    final statusColor  = ready ? primary : (exhausted ? Colors.red.shade700 : Colors.orange.shade700);
    final statusLabel  = ready ? 'Conectado' : (exhausted ? 'Desconectado — requiere reinicio manual' : 'Reconectando…');

    return AppCard(
      child: s == null
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(color: primary, strokeWidth: 2)),
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(statusLabel,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: statusColor))),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Actualizar',
                onPressed: _loadBotStatus,
              ),
            ]),
            const Divider(height: 20),
            _statRow(Icons.pending_actions_outlined, 'Mensajes en cola', '${s['pendingQueue'] ?? 0}'),
            _statRow(Icons.send_outlined, 'Enviados última hora',
              '${s['sentLastHour'] ?? 0} / ${s['maxMsgsPerHour'] ?? '-'}'),
            _statRow(Icons.chat_bubble_outline, 'Último mensaje', _timeAgo(s['lastMessageAt'] as String?)),
            _statRow(Icons.autorenew, 'Reintentos de reconexión',
              '${s['reconnectAttempts'] ?? 0} / ${s['maxReconnectAttempts'] ?? '-'}'),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _restartingBot ? null : _restartBot,
                style: OutlinedButton.styleFrom(foregroundColor: primary),
                icon: _restartingBot
                    ? SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: primary, strokeWidth: 2))
                    : const Icon(Icons.restart_alt_rounded),
                label: Text(_restartingBot ? 'Reiniciando...' : 'Reiniciar bot'),
              ),
            ),
          ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Bot health section
        _sectionTitle('Estado del bot de WhatsApp'),
        _botStatusCard(),

        const SizedBox(height: 24),

        _sectionTitle('Personalización de marca'),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 10, runSpacing: 10, children: _presets.map((p) {
              final selected = _selectedPrimary == p['primary'];
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedPrimary = p['primary']!;
                  _selectedAccent  = p['accent']!;
                }),
                child: Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? Colors.black87 : Colors.transparent, width: 2),
                  ),
                  child: Row(children: [
                    Expanded(child: Container(color: Color(int.parse('FF${p['primary']!.replaceAll('#', '')}', radix: 16)))),
                    Expanded(child: Container(color: Color(int.parse('FF${p['accent']!.replaceAll('#', '')}', radix: 16)))),
                  ]),
                ),
              );
            }).toList()),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickLogo,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Cambiar logo'),
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
              child: AppButton(label: 'Guardar marca', onPressed: _saveBranding, loading: _savingBrand, icon: Icons.palette_outlined)),
          ]),
        ),
        const SizedBox(height: 24),

        // Empresa section
        _sectionTitle('Información de la empresa'),
        AppCard(
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

        const SizedBox(height: 24),

        // Nequi section
        _sectionTitle('Pago Nequi'),
        AppCard(
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

        const SizedBox(height: 24),

        AppButton(
          label: _saving ? 'Guardando...' : 'Guardar configuración',
          onPressed: _saving ? null : _save,
          loading: _saving,
          icon: Icons.save_rounded,
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}
