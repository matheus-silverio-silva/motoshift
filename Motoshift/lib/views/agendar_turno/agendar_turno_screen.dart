import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/repeticao_de_turno.dart';
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
  const AgendarTurnoScreen({this.origem, super.key});

  /// O turno que está sendo publicado de novo ("Publicar de novo"). Também
  /// chega pela rota: `pushNamed(AppRoutes.publicarTurno, arguments: turno)`.
  /// Nulo é o formulário em branco de sempre.
  final Turno? origem;

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

  /// Ponto de partida do turno: a loja, se o lojista a marcou em "Dados
  /// pessoais"; senão o GPS; senão o centro da cidade. Em qualquer caso, o
  /// toque no mapa tem a palavra final.
  ///
  /// Era uma constante fixa em Maringá-PR, enquanto o turno era gravado com
  /// `regiao: 'São Paulo'` e sem coordenada nenhuma — o mapa mostrava um lugar,
  /// o turno dizia outro, e o filtro "perto de mim" não achava nenhum dos dois.
  /// Depois passou a ser o GPS, que é onde o lojista está publicando — a casa
  /// dele, o celular na rua —, com o endereço da loja no texto: pino e
  /// endereço apontando para lugares diferentes.
  LatLng _centro = GeoReferencia.padrao;

  /// Origem do ponto atual — muda o texto de apoio abaixo do mapa.
  _OrigemDoPonto _origem = _OrigemDoPonto.padrao;

  bool _buscandoGps = false;

  /// Preenchida quando o formulário nasce de um turno anterior.
  RepeticaoDeTurno? _repeticao;
  bool _origemLida = false;

  /// Título e descrição do turno de origem, que o formulário não edita.
  /// Título nulo é o automático ("Turno dd/MM"), gerado pela data escolhida.
  String? _tituloFixo;
  String? _descricao;

  /// O endereço do turno de origem vale enquanto a região for a dele; se o
  /// lojista reescrever a região, o texto novo é o endereço, como sempre.
  String? _enderecoDaOrigem;

  @override
  void initState() {
    super.initState();
    // A pré-visualização do desktop mostra o valor enquanto ele é digitado.
    _valorCtrl.addListener(_aoDigitarValor);
    WidgetsBinding.instance.addPostFrameCallback((_) => _definirPontoInicial());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_origemLida) return;
    _origemLida = true;
    final daRota = ModalRoute.of(context)?.settings.arguments;
    final origem = widget.origem ?? (daRota is Turno ? daRota : null);
    if (origem != null) _preencherCom(origem);
  }

  /// Copia o turno de origem para o formulário. A data é a da
  /// [RepeticaoDeTurno]; o resto, igual.
  void _preencherCom(Turno origem) {
    final r = RepeticaoDeTurno.de(origem);
    _repeticao = r;
    _tituloFixo = r.titulo;
    _descricao = r.descricao;
    _data = DateTime(r.inicio.year, r.inicio.month, r.inicio.day);
    _horaInicio = TimeOfDay.fromDateTime(r.inicio);
    _horaFim = TimeOfDay.fromDateTime(r.fim);
    // Os limites são os dos controles: um turno antigo fora deles não pode
    // deixar o slider num valor que ele não sabe desenhar.
    _raio = origem.raioEntregaKm.clamp(1, 20).roundToDouble();
    _vagas = origem.vagas.clamp(1, 20);
    _valorCtrl.text =
        origem.valorEstimado.toStringAsFixed(2).replaceAll('.', ',');
    _regiaoCtrl.text = origem.regiao;
    _enderecoDaOrigem = origem.endereco;
    if (origem.latitude != null && origem.longitude != null) {
      _centro = LatLng(origem.latitude!, origem.longitude!);
      _origem = _OrigemDoPonto.repetido;
    }
  }

  /// Ordem de preferência para o ponto inicial: a loja cadastrada, o GPS e,
  /// enquanto o GPS não responde (ou se ele não responder), a cidade.
  Future<void> _definirPontoInicial() async {
    if (!mounted) return;
    final usuario = context.read<AuthService>().usuario;

    // Publicar de novo: região e ponto são os do turno de origem. O GPS nem é
    // consultado quando o ponto veio junto — é o lugar onde o turno já foi.
    if (_repeticao != null) {
      if (_origem == _OrigemDoPonto.repetido) return;
    } else {
      _regiaoCtrl.text = _regiaoDoCadastro(usuario);
    }

    // A loja marcada é o endereço que o texto diz: o GPS nem é consultado.
    if (usuario != null && usuario.temPontoDaLoja) {
      setState(() {
        _centro = LatLng(usuario.latitude!, usuario.longitude!);
        _origem = _OrigemDoPonto.loja;
      });
      return;
    }

    if (GeoReferencia.conhece(usuario?.cidade)) {
      setState(() {
        _centro = GeoReferencia.daCidade(usuario?.cidade);
        _origem = _OrigemDoPonto.cidade;
      });
    }

    setState(() => _buscandoGps = true);
    final pos = await LocalizacaoService.of(context).posicaoAtual();
    if (!mounted) return;
    setState(() {
      _buscandoGps = false;
      // O GPS responde quando responde. Se o lojista tocou o mapa nesse meio
      // tempo, o ponto dele vale mais que o do aparelho — antes o GPS chegava
      // depois e movia o pino sem avisar.
      if (pos.temPosicao && _origem.aceitaOGps) {
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
      // Preenchido (publicar de novo), o calendário abre na data sugerida.
      initialDate: _data ?? clock.now().add(const Duration(days: 1)),
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
          ? _horaInicio ?? const TimeOfDay(hour: 8, minute: 0)
          : _horaFim ?? const TimeOfDay(hour: 12, minute: 0),
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

  /// Mostra o custo e o saldo antes de publicar; sem saldo, oferece recarga.
  ///
  /// O backend recusa a publicação sem lastro com 422, e a mensagem dele já
  /// diz quanto falta. Mas descobrir isso só depois de preencher o formulário
  /// inteiro é descobrir tarde: aqui o lojista vê a conta antes de confirmar,
  /// e quando o saldo não dá, o caminho para resolver está no mesmo diálogo.
  ///
  /// Isto NÃO substitui a checagem do servidor. O saldo pode mudar entre esta
  /// leitura e a publicação — outro turno liquidando, um saque — e quem decide
  /// continua sendo o backend, dentro da transação.
  Future<bool> _confirmarCusto(Turno turno) async {
    final api = context.read<ApiService>();

    double? disponivel;
    try {
      disponivel = (await api.carteira.buscarResumo()).disponivel;
    } catch (_) {
      // Sem saldo em mãos, seguir em frente é melhor do que barrar: quem
      // decide é o servidor, e ele responde com o número certo.
      disponivel = null;
    }
    if (!mounted) return false;

    final custo = turno.valorEstimado * turno.vagas;
    final falta = disponivel == null ? 0.0 : custo - disponivel;
    final semSaldo = disponivel != null && falta > 0;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Confirmar publicação',
            style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _linhaDoCusto(
              'Custo do turno',
              _moeda(custo),
              detalhe: turno.vagas > 1
                  ? '${_moeda(turno.valorEstimado)} × ${turno.vagas} vagas'
                  : null,
              destaque: true,
            ),
            const SizedBox(height: 10),
            _linhaDoCusto(
              'Saldo disponível',
              disponivel == null ? '—' : _moeda(disponivel),
            ),
            const SizedBox(height: 14),
            Text(
              semSaldo
                  ? 'Faltam ${_moeda(falta)} para publicar este turno.'
                  : 'Este valor fica reservado na sua carteira até o turno ser '
                      'finalizado, cancelado ou vencer.',
              key: const Key('publicar-aviso-custo'),
              style: tsJakarta(12, FontWeight.w500,
                  color: semSaldo ? AppColors.error : AppColors.muted,
                  height: 1.45),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style:
                    tsJakarta(13, FontWeight.w600, color: AppColors.muted)),
          ),
          if (semSaldo)
            FilledButton(
              key: const Key('publicar-adicionar-saldo'),
              onPressed: () => Navigator.pop(ctx, null),
              style: FilledButton.styleFrom(backgroundColor: AppColors.amber),
              child: Text('Adicionar saldo',
                  style: tsJakarta(13, FontWeight.w700,
                      color: AppColors.onTertiary)),
            )
          else
            FilledButton(
              key: const Key('publicar-confirmar'),
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
              child: const Text('Publicar'),
            ),
        ],
      ),
    );

    if (!mounted) return false;

    // `null` é o "Adicionar saldo": leva para a recarga já com o que falta
    // preenchido e, se o crédito entrar, tenta de novo sem refazer o formulário.
    if (confirmado == null && semSaldo) {
      final creditou = await Navigator.of(context)
          .pushNamed(AppRoutes.recarga, arguments: falta);
      if (creditou == true && mounted) return _confirmarCusto(turno);
      return false;
    }
    return confirmado ?? false;
  }

  /// Pede ao lojista que confirme o ponto quando ele é só uma aproximação.
  ///
  /// "Marcar no mapa" devolve ao formulário; "Usar este ponto" aceita o que
  /// está no mapa. Os dois são decisões conscientes — o que não pode é o
  /// turno nascer no centro da cidade porque ninguém olhou para o mapa.
  Future<bool> _confirmarPonto() async {
    final cidade = context.read<AuthService>().usuario?.cidade?.trim();
    final onde = _origem == _OrigemDoPonto.cidade && cidade != null && cidade.isNotEmpty
        ? 'O mapa está no centro de $cidade, não no endereço da loja.'
        : 'Não sabemos onde fica a sua loja, e o mapa está num ponto padrão.';

    final usar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Confirme o ponto de partida',
            style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        content: Text(
          '$onde O entregador vai até o ponto do mapa. Toque no mapa para '
          'marcar o lugar certo — ou marque a loja uma vez em Dados pessoais '
          'e ela passa a ser o ponto de todo turno.',
          key: const Key('publicar-aviso-ponto'),
          style: tsJakarta(12.5, FontWeight.w500,
              color: AppColors.text, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Marcar no mapa',
                style: tsJakarta(13, FontWeight.w700, color: AppColors.teal)),
          ),
          FilledButton(
            key: const Key('publicar-usar-ponto'),
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
            child: const Text('Usar este ponto'),
          ),
        ],
      ),
    );
    if (usar == true && mounted) {
      setState(() => _origem = _OrigemDoPonto.escolhido);
    }
    return usar == true;
  }

  Widget _linhaDoCusto(String rotulo, String valor,
      {String? detalhe, bool destaque = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(rotulo,
                  style: tsJakarta(12.5, FontWeight.w600,
                      color: AppColors.text)),
              if (detalhe != null)
                Text(detalhe,
                    style: tsJakarta(10.5, FontWeight.w400,
                        color: AppColors.muted)),
            ],
          ),
        ),
        Text(valor,
            style: tsBricolage(destaque ? 16 : 14, FontWeight.w800,
                color: destaque ? AppColors.ink : AppColors.text)),
      ],
    );
  }

  static String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

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
    final endereco = _enderecoDaOrigem != null &&
            regiao == _repeticao?.origem.regiao.trim()
        ? _enderecoDaOrigem!
        : regiao;

    final turno = Turno(
      lojistId: auth.usuario!.id!,
      titulo: _tituloFixo ?? 'Turno ${DateFormat('dd/MM').format(inicio)}',
      descricao: _descricao,
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
      endereco: endereco,
      vagas: _vagas,
    );

    // Ponto que ninguém confirmou — o centro da cidade, ou o marco zero de
    // Curitiba quando nem a cidade é conhecida — não vira turno em silêncio.
    if (_origem.precisaConfirmar && !await _confirmarPonto()) {
      if (mounted) setState(() => _publicando = false);
      return;
    }
    if (!mounted) return;

    // Publicar compromete dinheiro: o custo total sai do saldo disponível e
    // fica bloqueado até o turno encerrar. A confirmação mostra os dois
    // números antes de o lojista decidir — publicar deixou de ser um ato
    // gratuito, e a tela precisa dizer isso.
    if (!await _confirmarCusto(turno)) {
      if (mounted) setState(() => _publicando = false);
      return;
    }
    if (!mounted) return;

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
      // `true` avisa quem abriu (a lista, o "Publicar de novo") que há turno
      // novo para mostrar.
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context, true);
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
        title: 'Publicar turno',
        // Sem onBack: "Publicar turno" é item de menu, então chega-se aqui
        // por troca de seção, com a pilha vazia. O onBack fixo em pop()
        // forçava a seta e, tocada, desempilhava a última rota e deixava a
        // tela preta. Sem ele o AppHeader decide: seta quando há para onde
        // voltar, menu quando não há.
      ),
      desktopTitle: 'Publicar turno',
      desktopSubtitle: 'Defina data, horário e valor para sua operação',
      rotaDaSecao: AppRoutes.publicarTurno,
      desktopBody: _buildDesktop(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _repeticao == null ? 'Novo turno' : 'Publicar de novo',
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
              if (_repeticao != null) ...[
                _buildAvisoDaRepeticao(_repeticao!),
                const SizedBox(height: 14),
              ],
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
                if (_repeticao != null) ...[
                  _buildAvisoDaRepeticao(_repeticao!),
                  const SizedBox(height: 16),
                ],
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
    final titulo = _tituloFixo ??
        (_data != null
            ? 'Turno ${DateFormat('dd/MM').format(_data!)}'
            : 'Novo turno');

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

  /// O que veio do turno de origem e o que mudou — a data. Nada é publicado
  /// por estar preenchido: o botão e a confirmação do custo são os mesmos.
  Widget _buildAvisoDaRepeticao(RepeticaoDeTurno r) {
    final nome = r.origem.titulo.trim();
    return Container(
      key: const Key('aviso-repeticao'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.replay_rounded, size: 18, color: AppColors.tealDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Copiado de "$nome": mesmo lugar, raio, valor, vagas e horário. '
              'A data foi para ${r.dataPorExtenso}. Confira antes de publicar.',
              style: tsJakarta(12, FontWeight.w600,
                  color: AppColors.tealDeep, height: 1.45),
            ),
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
  loja,
  escolhido,

  /// O ponto do turno que está sendo publicado de novo.
  repetido;

  /// O GPS só substitui o que é palpite. Loja cadastrada e ponto tocado no
  /// mapa são decisões do lojista.
  bool get aceitaOGps =>
      this == _OrigemDoPonto.padrao || this == _OrigemDoPonto.cidade;

  /// Ponto que ninguém confirmou: publicar pergunta antes.
  bool get precisaConfirmar =>
      this == _OrigemDoPonto.padrao || this == _OrigemDoPonto.cidade;

  IconData get icone => switch (this) {
        _OrigemDoPonto.gps => Icons.my_location_rounded,
        _OrigemDoPonto.loja => Icons.storefront_rounded,
        _OrigemDoPonto.escolhido => Icons.touch_app_outlined,
        _OrigemDoPonto.repetido => Icons.replay_rounded,
        _ => Icons.info_outline_rounded,
      };

  String get explicacao => switch (this) {
        _OrigemDoPonto.gps =>
          'Posição atual do aparelho. Toque no mapa para ajustar.',
        _OrigemDoPonto.loja =>
          'Ponto da sua loja, marcado em Dados pessoais. Toque no mapa para '
              'ajustar só este turno.',
        _OrigemDoPonto.escolhido => 'Ponto escolhido por você no mapa.',
        _OrigemDoPonto.repetido =>
          'Mesmo ponto do turno de origem. Toque no mapa para ajustar.',
        _OrigemDoPonto.cidade =>
          'Centro aproximado da sua cidade. Toque no mapa para marcar o ponto exato.',
        _OrigemDoPonto.padrao =>
          'Ponto ainda não confirmado. Toque no mapa para marcar de onde o turno parte.',
      };
}
