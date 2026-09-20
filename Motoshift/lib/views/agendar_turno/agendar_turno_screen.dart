import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../models/usuario.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/geo_referencia.dart';
import '../../services/localizacao_service.dart';
import '../../services/preco_recomendado.dart';
import '../../routes/app_routes.dart';
import 'agendar_turno_campos.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/shift_row.dart';
import '../../widgets/mapa_raio.dart';
import '../../widgets/status_pill.dart';

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
  int _vagas = 1;
  final _valorCtrl = TextEditingController();
  final _regiaoCtrl = TextEditingController();
  bool _publicando = false;

  /// Ponto de partida do turno. Começa no centro da cidade do lojista, tenta
  /// subir para o GPS e termina onde ele tocar no mapa.
  ///
  /// Era uma constante fixa em Maringá-PR, enquanto o turno era gravado com
  /// `regiao: 'São Paulo'` e sem coordenada nenhuma — o mapa mostrava um lugar,
  /// o turno dizia outro, e o filtro "perto de mim" não achava nenhum dos dois.
  LatLng _centro = GeoReferencia.padrao;

  /// Origem do ponto atual — muda o texto de apoio abaixo do mapa.
  _OrigemDoPonto _origem = _OrigemDoPonto.padrao;

  bool _buscandoGps = false;

  @override
  void initState() {
    super.initState();
    // A pré-visualização do desktop mostra o valor enquanto ele é digitado.
    _valorCtrl.addListener(_aoDigitarValor);
    WidgetsBinding.instance.addPostFrameCallback((_) => _definirPontoInicial());
  }

  /// Ordem de preferência para o ponto inicial: cidade do cadastro (imediato)
  /// e, se o aparelho deixar, a posição real do GPS.
  Future<void> _definirPontoInicial() async {
    if (!mounted) return;
    final usuario = context.read<AuthService>().usuario;

    _regiaoCtrl.text = _regiaoDoCadastro(usuario);
    if (GeoReferencia.conhece(usuario?.cidade)) {
      setState(() {
        _centro = GeoReferencia.daCidade(usuario?.cidade);
        _origem = _OrigemDoPonto.cidade;
      });
    }

    setState(() => _buscandoGps = true);
    final pos = await const LocalizacaoService().posicaoAtual();
    if (!mounted) return;
    setState(() {
      _buscandoGps = false;
      if (pos.temPosicao) {
        _centro = LatLng(pos.latitude!, pos.longitude!);
        _origem = _OrigemDoPonto.gps;
      }
    });
  }

  /// Região sugerida a partir do cadastro do lojista: endereço comercial
  /// quando houver, senão cidade/UF. Antes era a string fixa "São Paulo".
  String _regiaoDoCadastro(Usuario? usuario) {
    final endereco = usuario?.enderecoComercial?.trim();
    if (endereco != null && endereco.isNotEmpty) return endereco;
    final cidade = usuario?.cidade?.trim();
    final estado = usuario?.estado?.trim();
    if (cidade != null && cidade.isNotEmpty) {
      return estado != null && estado.isNotEmpty ? '$cidade/$estado' : cidade;
    }
    return '';
  }

  void _escolherPonto(LatLng ponto) {
    setState(() {
      _centro = ponto;
      _origem = _OrigemDoPonto.escolhido;
    });
  }

  void _aoDigitarValor() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _valorCtrl.removeListener(_aoDigitarValor);
    _valorCtrl.dispose();
    _regiaoCtrl.dispose();
    super.dispose();
  }

  /// Sugestão de preço — só disponível quando data e horários estão definidos.
  PrecoResultado? get _recomendacao {
    if (_data == null || _horaInicio == null || _horaFim == null) return null;
    final inicio = DateTime(_data!.year, _data!.month, _data!.day,
        _horaInicio!.hour, _horaInicio!.minute);
    final fim = DateTime(_data!.year, _data!.month, _data!.day,
        _horaFim!.hour, _horaFim!.minute);
    if (!fim.isAfter(inicio)) return null;
    return PrecoRecomendado.calcular(
        inicio: inicio, fim: fim, raioKm: _raio);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: clock.now().add(const Duration(days: 1)),
      firstDate: clock.now(),
      lastDate: clock.now().add(const Duration(days: 90)),
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
      initialEntryMode: TimePickerEntryMode.inputOnly,
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

    if (inicio.isBefore(clock.now().add(const Duration(hours: 2)))) {
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

    final regiao = _regiaoCtrl.text.trim().isEmpty
        ? 'Região não informada'
        : _regiaoCtrl.text.trim();

    final turno = Turno(
      lojistId: auth.usuario!.id!,
      titulo: 'Turno ${DateFormat('dd/MM').format(inicio)}',
      regiao: regiao,
      dataInicio: inicio,
      dataFim: fim,
      valorEstimado:
          double.tryParse(_valorCtrl.text.replaceAll(',', '.')) ?? 0.0,
      raioEntregaKm: _raio,
      // Sem estas duas o turno nascia sem ponto de partida e nunca aparecia no
      // filtro por raio do entregador — o backend aceita desde o SCRUM-18,
      // era o app que não mandava.
      latitude: _centro.latitude,
      longitude: _centro.longitude,
      endereco: regiao,
      vagas: _vagas,
    );

    try {
      await api.turnos.criarTurno(turno);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Turno publicado com sucesso!'),
          backgroundColor: AppColors.teal,
        ),
      );
      // Voltar só existe se houver para onde: publicar virou item de menu, e
      // pela barra lateral esta tela é a única da pilha — um `pop` seco ali
      // deixaria o Navigator vazio. Sem pilha, segue para a lista de turnos,
      // que é onde o turno recém-publicado aparece.
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.turnosLojista);
      }
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
    return AdaptiveScaffold(
      header: AppHeader.back(
        title: 'Publicar Turno',
        onBack: () => Navigator.pop(context),
      ),
      desktopTitle: 'Publicar turno',
      desktopSubtitle: 'Defina data, horário e valor para sua operação',
      desktopSelectedRoute: AppRoutes.publicarTurno,
      desktopBody: _buildDesktop(),
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
                  Expanded(child: CardData(data: _data, onEscolher: _pickDate)),
                  const SizedBox(width: 10),
                  Expanded(child: CardHorario(inicio: _horaInicio, fim: _horaFim, onEscolherInicio: () => _pickTime(true), onEscolherFim: () => _pickTime(false))),
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
                    SecaoRaio(raioKm: _raio, onMudar: (v) => setState(() => _raio = v)),
                    const SizedBox(height: 22),
                    SecaoVagas(vagas: _vagas, onMudar: (v) => setState(() => _vagas = v)),
                    const SizedBox(height: 22),
                    _buildValorSection(),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildPontoDePartida(),
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

  // ── Desktop — formulário em 2 colunas + pré-visualização ao vivo ─────────

  Widget _buildDesktop() {
    return Form(
      key: _formKey,
      child: ContentGrid(
        children: [
          GridCol(
            span: 7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: CardData(data: _data, onEscolher: _pickDate)),
                      const SizedBox(width: 16),
                      Expanded(child: CardHorario(inicio: _horaInicio, fim: _horaFim, onEscolherInicio: () => _pickTime(true), onEscolherFim: () => _pickTime(false))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line, width: 1.5),
                  ),
                  child: Column(
                    children: [
                      SecaoRaio(raioKm: _raio, onMudar: (v) => setState(() => _raio = v)),
                      const SizedBox(height: 24),
                      SecaoVagas(vagas: _vagas, onMudar: (v) => setState(() => _vagas = v)),
                      const SizedBox(height: 24),
                      _buildValorSection(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GridCol(
            span: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPreview(),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.amberSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 20, color: AppColors.onTertiaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Agende com pelo menos 2 h de antecedência. O valor '
                          'fica bloqueado na carteira até a conclusão.',
                          style: tsJakarta(12, FontWeight.w600,
                              color: AppColors.onTertiaryContainer, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Publicar turno',
                  loading: _publicando,
                  onPressed: _publicar,
                  icon: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(height: 10),
                Text(
                  'Ao publicar, o turno ficará visível para entregadores na '
                  'região.',
                  textAlign: TextAlign.center,
                  style:
                      tsJakarta(11.5, FontWeight.w400, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Pré-visualização ao vivo: reflete o que já foi preenchido, sem inventar
  /// o que falta — campo vazio aparece como travessão.
  Widget _buildPreview() {
    final valor = double.tryParse(_valorCtrl.text.replaceAll(',', '.'));
    final horario = (_horaInicio != null && _horaFim != null)
        ? '${_fmtHora(_horaInicio!)} – ${_fmtHora(_horaFim!)}'
        : '--:-- – --:--';
    final titulo = _data != null
        ? 'Turno ${DateFormat('dd/MM').format(_data!)}'
        : 'Novo turno';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Pré-visualização',
                  style:
                      tsBricolage(16, FontWeight.w800, color: AppColors.ink)),
              const SizedBox(width: 8),
              const StatusPill(label: 'como o entregador vê'),
            ],
          ),
          const SizedBox(height: 14),
          ShiftRow(
            horario: horario,
            valor: valor == null
                ? 'R\$ --'
                : 'R\$ ${valor.toStringAsFixed(0)}',
            meta: '$titulo · ${_raio.toStringAsFixed(0)} km',
            icon: Icons.two_wheeler_outlined,
            pillLabel:
                _vagas == 1 ? '1 vaga' : '$_vagas vagas',
            pillVariant: PillVariant.ghost,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 200,
            child: MapaRaio(
              centro: _centro,
              raioKm: _raio,
              height: 200,
              onTapMapa: _escolherPonto,
              rodape: _regiaoCtrl.text.trim().isEmpty
                  ? null
                  : _regiaoCtrl.text.trim(),
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Custo do turno',
                        style: tsJakarta(12.5, FontWeight.w700,
                            color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text(
                      '${_vagas == 1 ? '1 vaga' : '$_vagas vagas'} × '
                      '${valor == null ? 'R\$ --' : 'R\$ ${valor.toStringAsFixed(0)}'}',
                      style: tsJakarta(11.5, FontWeight.w400,
                          color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Text(
                valor == null
                    ? '—'
                    : 'R\$ ${(valor * _vagas).toStringAsFixed(0)}',
                style: tsBricolage(16, FontWeight.w800, color: AppColors.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtHora(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// De onde o turno parte: a região em texto e o ponto no mapa.
  ///
  /// O mapa é tocável de propósito — é a única forma honesta de o lojista
  /// corrigir o ponto sem uma geocodificação de endereço, que este MVP não
  /// tem. O que ele confirmar aqui é o que vai para o banco e o que o filtro
  /// por distância do entregador usa.
  Widget _buildPontoDePartida() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined, color: AppColors.teal, size: 14),
              const SizedBox(width: 5),
              Text('PONTO DE PARTIDA',
                  style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)
                      .copyWith(letterSpacing: 0.9)),
              const Spacer(),
              if (_buscandoGps)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.teal),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _regiaoCtrl,
            onChanged: (_) => setState(() {}),
            style: tsJakarta(13, FontWeight.w600, color: AppColors.ink),
            decoration: InputDecoration(
              hintText: 'Bairro ou endereço de partida',
              hintStyle:
                  tsJakarta(12.5, FontWeight.w400, color: AppColors.muted),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.line, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.line, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.teal, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 10),
          MapaRaio(
            centro: _centro,
            raioKm: _raio,
            height: 180,
            onTapMapa: _escolherPonto,
            rodape:
                _regiaoCtrl.text.trim().isEmpty ? null : _regiaoCtrl.text.trim(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(_origem.icone, size: 13, color: AppColors.muted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _origem.explicacao,
                  style:
                      tsJakarta(10.5, FontWeight.w400, color: AppColors.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Copia o valor recomendado para o campo e revalida o formulário — o campo
  /// tem regra própria de mínimo, e ela precisa rodar sobre o valor novo.
  void _usarValorRecomendado(double valor) {
    setState(() =>
        _valorCtrl.text = valor.toStringAsFixed(2).replaceAll('.', ','));
    _formKey.currentState?.validate();
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
        CardRecomendacao(recomendacao: _recomendacao, onUsarValor: _usarValorRecomendado),
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

/// De onde veio o ponto que está no mapa. O lojista precisa saber se aquilo é
/// um chute pela cidade do cadastro ou a posição real do aparelho — sem isso,
/// um centro aproximado passa por preciso e o turno nasce no lugar errado.
enum _OrigemDoPonto {
  padrao,
  cidade,
  gps,
  escolhido;

  IconData get icone => switch (this) {
        _OrigemDoPonto.gps => Icons.my_location_rounded,
        _OrigemDoPonto.escolhido => Icons.touch_app_outlined,
        _ => Icons.info_outline_rounded,
      };

  String get explicacao => switch (this) {
        _OrigemDoPonto.gps =>
          'Posição atual do aparelho. Toque no mapa para ajustar.',
        _OrigemDoPonto.escolhido => 'Ponto escolhido por você no mapa.',
        _OrigemDoPonto.cidade =>
          'Centro aproximado da sua cidade. Toque no mapa para marcar o ponto exato.',
        _OrigemDoPonto.padrao =>
          'Ponto ainda não confirmado. Toque no mapa para marcar de onde o turno parte.',
      };
}
