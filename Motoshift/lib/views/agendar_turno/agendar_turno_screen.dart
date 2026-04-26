import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kinetic_app_bar.dart';
import '../../widgets/kinetic_bottom_nav.dart';
import '../../widgets/kinetic_button.dart';

class AgendarTurnoScreen extends StatefulWidget {
  const AgendarTurnoScreen({super.key});

  @override
  State<AgendarTurnoScreen> createState() => _AgendarTurnoScreenState();
}

class _AgendarTurnoScreenState extends State<AgendarTurnoScreen> {
  final _formKey = GlobalKey<FormState>();

  DateTime? _data;
  TimeOfDay? _horaInicio;
  TimeOfDay? _horaFim;
  double _raio = 15;
  final _valorCtrl = TextEditingController();
  bool _publicando = false;

  @override
  void dispose() {
    _valorCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: AppColors.surfaceContainerLowest,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _data = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? const TimeOfDay(hour: 8, minute: 0)
          : const TimeOfDay(hour: 12, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) _horaInicio = picked; else _horaFim = picked;
      });
    }
  }

  Future<void> _publicar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_data == null || _horaInicio == null || _horaFim == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha data e horário do turno'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _publicando = true);

    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();

    final inicio = DateTime(
      _data!.year, _data!.month, _data!.day,
      _horaInicio!.hour, _horaInicio!.minute,
    );
    final fim = DateTime(
      _data!.year, _data!.month, _data!.day,
      _horaFim!.hour, _horaFim!.minute,
    );

    // RF04: antecedencia minima de 2 horas
    if (inicio.isBefore(DateTime.now().add(const Duration(hours: 2)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Antecedencia Minima Insuficiente: agende com pelo menos 2 horas de antecedencia.'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _publicando = false);
      return;
    }

    if (!fim.isAfter(inicio)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O horario de fim deve ser posterior ao horario de inicio.'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _publicando = false);
      return;
    }

    final turno = Turno(
      lojistId: auth.usuario!.id!,
      titulo: 'Turno ${DateFormat('dd/MM').format(inicio)}',
      regiao: 'São Paulo',
      dataInicio: inicio,
      dataFim: fim,
      valorEstimado:
          double.tryParse(_valorCtrl.text.replaceAll(',', '.')) ?? 0.0,
      raioEntregaKm: _raio,
    );

    try {
      await api.criarTurno(turno);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Turno publicado com sucesso!'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: KineticAppBar(
        avatarUrl: auth.usuario?.fotoPerfil,
        onNotificationTap: () {},
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 96, 24, 120),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header editorial ──
              const Text(
                'Novo Turno',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Defina a logística da sua operação para os próximos dias.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 15,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              // ── Data + Horário ──
              Row(
                children: [
                  Expanded(child: _buildDataCard()),
                  const SizedBox(width: 12),
                  Expanded(child: _buildHorarioCard()),
                ],
              ),
              const SizedBox(height: 20),

              // ── Parâmetros logísticos ──
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Raio
                    _buildRaioSection(),
                    const SizedBox(height: 28),
                    // Valor
                    _buildValorSection(),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Mapa decorativo ──
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 120,
                  color: AppColors.surfaceContainerHigh,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const Icon(Icons.map_outlined,
                          size: 56, color: AppColors.outlineVariant),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              AppColors.surfaceContainerLow,
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ── Botão publicar ──
              KineticButton(
                label: 'Publicar Turno',
                loading: _publicando,
                onPressed: _publicar,
                icon: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ao publicar, o turno ficará visível para todos os entregadores qualificados na região.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  color: AppColors.outline,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: KineticBottomNav(
        currentItem: NavItem.turnos,
        onItemSelected: (_) => Navigator.pop(context),
      ),
    );
  }

  // ── Data card ────────────────────────────────────────────
  Widget _buildDataCard() {
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    color: AppColors.primary, size: 18),
                SizedBox(width: 8),
                Text(
                  'DATA DO TURNO',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _data != null
                    ? DateFormat('dd/MM/yyyy').format(_data!)
                    : 'Selecionar',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _data != null
                      ? AppColors.onSurface
                      : AppColors.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Horário card ─────────────────────────────────────────
  Widget _buildHorarioCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.schedule_outlined,
                  color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text(
                'JANELA HORÁRIA',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickTime(true),
                  child: _timeChip(_horaInicio),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('às',
                    style: TextStyle(color: AppColors.outline, fontSize: 13)),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickTime(false),
                  child: _timeChip(_horaFim),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeChip(TimeOfDay? t) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        t != null
            ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
            : '--:--',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: t != null ? AppColors.onSurface : AppColors.outline,
        ),
      ),
    );
  }

  // ── Raio slider ──────────────────────────────────────────
  Widget _buildRaioSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Row(
              children: [
                Icon(Icons.straighten_outlined,
                    color: AppColors.primary, size: 18),
                SizedBox(width: 8),
                Text(
                  'RAIO DE ENTREGA',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryFixed,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Até ${_raio.toStringAsFixed(0)} km',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onPrimaryFixed,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.surfaceContainerHighest,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withOpacity(0.15),
            trackHeight: 4,
          ),
          child: Slider(
            value: _raio,
            min: 1,
            max: 20,
            divisions: 19,
            onChanged: (v) => setState(() => _raio = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('1km', style: _rangeStyle),
              Text('5km', style: _rangeStyle),
              Text('10km', style: _rangeStyle),
              Text('15km', style: _rangeStyle),
              Text('20km+', style: _rangeStyle),
            ],
          ),
        ),
      ],
    );
  }

  static const _rangeStyle = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 1,
    color: AppColors.outline,
  );

  // ── Valor do turno ───────────────────────────────────────
  Widget _buildValorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.payments_outlined, color: AppColors.primary, size: 18),
            SizedBox(width: 8),
            Text(
              'VALOR DO TURNO',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _valorCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
          decoration: InputDecoration(
            prefixText: 'R\$ ',
            prefixStyle: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceVariant,
            ),
            hintText: '0,00',
            hintStyle: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.outlineVariant,
            ),
            filled: true,
            fillColor: AppColors.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Informe o valor do turno';
            final valor = double.tryParse(v.replaceAll(',', '.'));
            if (valor == null || valor <= 0) return 'O valor deve ser maior que zero';
            return null;
          },
        ),
        const SizedBox(height: 10),
        const Text(
          'O valor será creditado na carteira do entregador logo após a conclusão do turno.',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            color: AppColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
