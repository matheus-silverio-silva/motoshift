import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/mapa_raio.dart';

class AgendarTurnoScreen extends StatefulWidget {
  const AgendarTurnoScreen({super.key});

  @override
  State<AgendarTurnoScreen> createState() => _AgendarTurnoScreenState();
}

class _AgendarTurnoScreenState extends State<AgendarTurnoScreen> {
  final _formKey = GlobalKey<FormState>();

  static const _centro = LatLng(-23.4273, -51.9375); // Maringá-PR

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
            primary: AppColors.teal,
            onPrimary: Colors.white,
            surface: AppColors.surface,
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
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.teal,
              onPrimary: Colors.white,
              surface: AppColors.surface,
            ),
          ),
          child: child!,
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) _horaInicio = picked;
        else _horaFim = picked;
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

    if (inicio.isBefore(DateTime.now().add(const Duration(hours: 2)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Antecedência mínima insuficiente: agende com pelo menos 2 horas de antecedência.'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _publicando = false);
      return;
    }

    if (!fim.isAfter(inicio)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'O horário de fim deve ser posterior ao horário de início.'),
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
          backgroundColor: AppColors.teal,
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
    return AppScaffold(
      header: AppHeader.back(
        title: 'Publicar Turno',
        onBack: () => Navigator.pop(context),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Novo turno',
                style: tsBricolage(20, FontWeight.w800,
                    color: AppColors.ink),
              ),
              const SizedBox(height: 3),
              Text(
                'Defina data, horário e valor para sua operação.',
                style: tsJakarta(12, FontWeight.w400,
                    color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              // Data + Horário
              Row(
                children: [
                  Expanded(child: _buildDataCard()),
                  const SizedBox(width: 10),
                  Expanded(child: _buildHorarioCard()),
                ],
              ),
              const SizedBox(height: 14),
              // Raio + Valor
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line, width: 1.5),
                ),
                child: Column(
                  children: [
                    _buildRaioSection(),
                    const SizedBox(height: 22),
                    _buildValorSection(),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              MapaRaio(
                centro: _centro,
                raioKm: _raio,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Publicar Turno',
                loading: _publicando,
                onPressed: _publicar,
                icon: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(height: 10),
              Text(
                'Ao publicar, o turno ficará visível para entregadores na região.',
                textAlign: TextAlign.center,
                style: tsJakarta(10.5, FontWeight.w400,
                    color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataCard() {
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  color: AppColors.teal, size: 14),
              const SizedBox(width: 5),
              Text('DATA',
                  style: tsJakarta(9, FontWeight.w700,
                      color: AppColors.teal)),
            ]),
            const SizedBox(height: 10),
            Text(
              _data != null
                  ? DateFormat('dd/MM/yyyy', 'pt_BR').format(_data!)
                  : 'Selecionar',
              style: tsJakarta(13, FontWeight.w600,
                  color: _data != null
                      ? AppColors.ink
                      : AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorarioCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.schedule_outlined,
                color: AppColors.teal, size: 14),
            const SizedBox(width: 5),
            Text('HORÁRIO',
                style: tsJakarta(9, FontWeight.w700,
                    color: AppColors.teal)),
          ]),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickTime(true),
                  child: _timeChip(_horaInicio),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text('—',
                    style: tsJakarta(12, FontWeight.w400,
                        color: AppColors.muted)),
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
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        t != null
            ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
            : '--:--',
        textAlign: TextAlign.center,
        style: tsJakarta(13, FontWeight.w600,
            color: t != null ? AppColors.ink : AppColors.muted),
      ),
    );
  }

  Widget _buildRaioSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Row(children: [
              const Icon(Icons.straighten_outlined,
                  color: AppColors.teal, size: 14),
              const SizedBox(width: 5),
              Text('RAIO DE ENTREGA',
                  style: tsJakarta(9, FontWeight.w700,
                      color: AppColors.teal)),
            ]),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Até ${_raio.toStringAsFixed(0)} km',
                style: tsJakarta(9.5, FontWeight.w700,
                    color: AppColors.tealDeep),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.teal,
            inactiveTrackColor: AppColors.surface3,
            thumbColor: AppColors.teal,
            overlayColor: AppColors.teal.withOpacity(0.15),
            trackHeight: 3,
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
            children: ['1km', '5km', '10km', '15km', '20km+']
                .map((s) => Text(s,
                    style: tsJakarta(9, FontWeight.w700,
                        color: AppColors.muted)))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildValorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.payments_outlined,
              color: AppColors.teal, size: 14),
          const SizedBox(width: 5),
          Text('VALOR DO TURNO',
              style: tsJakarta(9, FontWeight.w700,
                  color: AppColors.teal)),
        ]),
        const SizedBox(height: 10),
        TextFormField(
          controller: _valorCtrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: tsBricolage(24, FontWeight.w800, color: AppColors.ink),
          decoration: InputDecoration(
            prefixText: 'R\$ ',
            prefixStyle: tsJakarta(16, FontWeight.w600,
                color: AppColors.muted),
            hintText: '0,00',
            hintStyle: tsBricolage(24, FontWeight.w800,
                color: AppColors.line),
            filled: true,
            fillColor: AppColors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.teal, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Informe o valor';
            final valor =
                double.tryParse(v.replaceAll(',', '.'));
            if (valor == null || valor <= 0)
              return 'Valor deve ser maior que zero';
            return null;
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Creditado na carteira do entregador após a conclusão.',
          style: tsJakarta(10.5, FontWeight.w400,
              color: AppColors.muted),
        ),
      ],
    );
  }
}
