// Helpers compartilhados para golden tests.
//
// - Carrega fontes em modo offline (GoogleFonts.allowRuntimeFetching = false)
// - Inicializa locale pt_BR
// - Bloqueia todo HTTP de rede (mapa OSM, etc) com HttpOverrides
// - Provê fakes para ApiService, AuthService e providers usados pelas telas
// - Helper pumpGolden() monta MaterialApp com locale, providers e args de rota

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:moto_shift/models/carteira.dart';
import 'package:moto_shift/models/cobranca.dart';
import 'package:moto_shift/models/danfse.dart';
import 'package:moto_shift/models/dre.dart';
import 'package:moto_shift/models/lancamento_gerencial.dart';
import 'package:moto_shift/models/documento_fiscal.dart';
import 'package:moto_shift/models/extrato_filtro.dart';
import 'package:moto_shift/models/informe_anual.dart';
import 'package:moto_shift/models/nota_fiscal.dart';
import 'package:moto_shift/models/nota_fiscal_filtro.dart';
import 'package:moto_shift/models/perfil_publico.dart';
import 'package:moto_shift/models/resumo_financeiro.dart';
import 'package:moto_shift/models/transacao.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/presentation/providers/turno_provider.dart';
import 'package:moto_shift/presentation/providers/turno_selecionado_provider.dart';
import 'package:moto_shift/presentation/providers/notificacao_provider.dart';
import 'package:moto_shift/presentation/providers/pendencias_provider.dart';
import 'package:moto_shift/presentation/providers/favoritos_provider.dart';
import 'package:moto_shift/models/entregador_favorito.dart';
import 'package:moto_shift/services/api/favorito_api.dart';
import 'package:moto_shift/services/api/agenda_api.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/auth_api.dart';
import 'package:moto_shift/services/api/nota_fiscal_api.dart';
import 'package:moto_shift/services/api/avaliacao_api.dart';
import 'package:moto_shift/services/api/carteira_api.dart';
import 'package:moto_shift/services/api/dashboard_api.dart';
import 'package:moto_shift/services/api/financeiro_api.dart';
import 'package:moto_shift/services/api/notificacao_api.dart';
import 'package:moto_shift/services/api/status_api.dart';
import 'package:moto_shift/services/api/turno_api.dart';
import 'package:moto_shift/services/api/usuario_api.dart';
import 'package:moto_shift/services/api_service.dart';
import 'package:moto_shift/services/auth_service.dart';
import 'package:moto_shift/services/localizacao_service.dart';
import 'package:moto_shift/theme/app_theme.dart';
import 'package:moto_shift/utils/baixar_arquivo.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Setup global
// ─────────────────────────────────────────────────────────────────────────────

/// Chame em setUpAll() de cada test file.
///
/// - Bloqueia todo HTTP (tiles OSM, fontes): a suíte não depende de rede
/// - Registra as fontes do tema (Bricolage Grotesque + Plus Jakarta Sans) a
///   partir dos arquivos embarcados em assets/fonts — os goldens mostram a
///   fonte que o usuário vê, e não a do sistema de quem rodou o teste.
/// - Registra a fonte dos ícones (MaterialIcons): sem ela todo ícone é um
///   quadrado no golden, e trocar um ícone por outro não muda a foto.
Future<void> setupGoldenTests() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  HttpOverrides.global = _SelectiveHttpOverrides();
  // Como no main.dart: fonte só dos assets. Um peso que o app passe a usar
  // sem embarcar o arquivo aparece aqui como erro, em vez de ser baixado.
  GoogleFonts.config.allowRuntimeFetching = false;
  await _registrarFontesDoTema();
  await _registrarFontesDeIcones();

  // Mock dos canais nativos usados em testes:
  // - path_provider: google_fonts salva fontes no diretório de suporte
  // - shared_preferences: AuthService persiste sessão
  final binMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  binMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.path,
  );

  binMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    (call) async {
      if (call.method == 'getAll') return <String, Object>{};
      return null;
    },
  );

  // Silencia avisos residuais de teste (tiles do mapa, timers).
  //
  // "RenderFlex overflowed" NÃO está mais nesta lista. Estava porque os
  // testes desenhavam com a fonte do sistema, de métricas diferentes das do
  // app, e todo estouro era tratado como artefato de teste. Com as fontes do
  // tema embarcadas, um estouro aqui é o estouro que o usuário vê no celular
  // — o primeiro que apareceu foi a linha do extrato, 16 px além da tela.
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exceptionAsString();
    if (msg.contains('google_fonts') ||
        msg.contains('Failed to load font') ||
        msg.contains('tile.openstreetmap') ||
        msg.contains('Timer is still pending') ||
        msg.contains('timersPending')) {
      return;
    }
    FlutterError.dumpErrorToConsole(details);
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Fakes de dados
// ─────────────────────────────────────────────────────────────────────────────

/// Base de tempo dos fakes: hoje à meia-noite.
///
/// Os fakes usavam `DateTime.now()` cru. Como os cards renderizam
/// `horarioFormatado` em HH:mm, o golden mudava **a cada minuto** — o snapshot
/// nascia desatualizado e a suíte ficava vermelha sozinha, sem ninguém tocar em
/// código. Ancorando na meia-noite, os horários exibidos ficam estáveis ao
/// longo do dia e a relação "ontem / hoje / amanhã" continua valendo.
///
/// Telas que NÃO imprimem data absoluta usam esta base e ficam estáveis ao
/// longo do dia; as que imprimem recebem o [dataAncoraGolden] abaixo.
DateTime hojeAncorado() {
  // clock.now() e nao DateTime.now(): dentro de withClock, fixture e tela
  // precisam concordar sobre que dia e hoje.
  final agora = clock.now();
  return DateTime(agora.year, agora.month, agora.day);
}

/// Momento em que os goldens desta suíte foram gravados.
///
/// Tudo que a tela deriva do relógio — o anel do "hoje" no calendário, a
/// saudação por faixa de hora, os rótulos dos sete dias do gráfico — precisa
/// receber esta data em vez de chamar `DateTime.now()`. Senão o golden só
/// passa no dia e na hora em que foi gerado, e uma suíte que já falha esconde
/// a próxima regressão de verdade.
final DateTime dataAncoraGolden = DateTime(2026, 8, 19, 14, 10);

Usuario fakeMotoboy() => Usuario(
      id: 1,
      nome: 'Ricardo Souza',
      email: 'ricardo@teste.com',
      telefone: '(41) 98111-2222',
      tipo: TipoUsuario.motoboy,
      documentoFederal: '12345678900',
      score: 4.7,
      mediaAvaliacao: 4.8,
      dataNascimento: DateTime(1995, 2, 10),
      cidade: 'Curitiba',
      estado: 'PR',
      cnhNumero: '12345678900',
      cnhCategoria: 'A',
      cnhValidade: DateTime(2028, 6, 30),
      veiculoModelo: 'Honda CG 160 Titan',
      veiculoPlaca: 'ABC-1D23',
      veiculoAno: 2022,
      veiculoCor: 'Vermelha',
      criadoEm: DateTime(2025, 1, 15),
    );

Usuario fakeLojista() => Usuario(
      id: 2,
      nome: 'Cláudia Oliveira',
      email: 'claudia@teste.com',
      telefone: '(41) 99111-2222',
      tipo: TipoUsuario.lojista,
      documentoFederal: '12.345.678/0001-90',
      // Lojista não tem score: a API não manda o campo.
      mediaAvaliacao: 4.8,
      dataNascimento: DateTime(1985, 3, 12),
      cidade: 'Curitiba',
      estado: 'PR',
      nomeFantasia: 'Hamburgueria da Cláudia',
      enderecoComercial: 'Av. Água Verde, 1200 — Água Verde, Curitiba/PR',
      criadoEm: DateTime(2025, 1, 1),
    );

List<Turno> fakeTurnosDisponiveis() {
  final base = clock.now().add(const Duration(days: 1));
  return [
    Turno(
      id: 101,
      lojistId: 2,
      titulo: 'Turno Tarde — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      dataInicio: DateTime(base.year, base.month, base.day, 14, 0),
      dataFim: DateTime(base.year, base.month, base.day, 18, 0),
      valorEstimado: 120,
      raioEntregaKm: 8,
    ),
    Turno(
      id: 102,
      lojistId: 3,
      titulo: 'Turno Manhã — Farmácia Ana',
      regiao: 'Centro Cívico, Curitiba',
      dataInicio: DateTime(base.year, base.month, base.day, 8, 0),
      dataFim: DateTime(base.year, base.month, base.day, 12, 0),
      valorEstimado: 110,
      raioEntregaKm: 6,
    ),
  ];
}

/// Turnos do motoboy, relativos a [ancora] (padrão: hoje à meia-noite).
///
/// O gráfico "ganhos dos últimos dias" do dashboard rotula os sete dias com o
/// dia da semana, e esses rótulos giram junto com o calendário. Passando a
/// mesma âncora do golden, a barra cai sempre no mesmo dia — ver
/// [FakeApiDatasFixas].
List<Turno> fakeMeusTurnos({DateTime? ancora}) {
  final hoje = ancora ?? hojeAncorado();
  return [
    Turno(
      id: 201,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Ativo — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      // Cobre o dia inteiro: continua "em andamento" a qualquer hora em que a
      // suíte rodar, e o horário exibido não muda ao longo do dia.
      dataInicio: hoje,
      dataFim: hoje.add(const Duration(hours: 23, minutes: 59)),
      valorEstimado: 120,
      raioEntregaKm: 8,
      status: StatusTurno.emAndamento,
      // Em andamento quer dizer que alguém fez check-in — é o que o backend
      // manda, e o que deixa "Confirmar conclusão" aparecer.
      algumCheckin: true,
    ),
    Turno(
      id: 202,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Concluído — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      dataInicio: hoje.subtract(const Duration(days: 7)),
      dataFim: hoje.subtract(const Duration(days: 7, hours: -4)),
      valorEstimado: 120,
      raioEntregaKm: 8,
      status: StatusTurno.finalizado,
      pagamentoStatus: PagamentoStatus.pago,
    ),
    Turno(
      id: 203,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Concluído — pendente pagamento',
      regiao: 'Água Verde, Curitiba',
      dataInicio: hoje.subtract(const Duration(days: 3)),
      dataFim: hoje.subtract(const Duration(days: 3, hours: -4)),
      valorEstimado: 125,
      raioEntregaKm: 8,
      status: StatusTurno.finalizado,
      pagamentoStatus: PagamentoStatus.pendente,
    ),
    // ── Aceitos e futuros: exercitam a seção "Próximos turnos" ──────────────
    // Sem estes dois a seção ficava vazia, e `_formatProximoData` ("Amanhã",
    // "Sáb", "Hoje") não era exercitado por teste nenhum — armadilha pronta
    // para o dia em que alguém acrescentasse um turno futuro aqui.
    Turno(
      id: 204,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Manhã — Padaria do Zé',
      regiao: 'Batel, Curitiba',
      // ramo "Amanhã"
      dataInicio: hoje.add(const Duration(days: 1, hours: 14)),
      dataFim: hoje.add(const Duration(days: 1, hours: 18)),
      valorEstimado: 130,
      raioEntregaKm: 6,
      status: StatusTurno.aceito,
    ),
    Turno(
      id: 205,
      lojistId: 3,
      motoboyId: 1,
      titulo: 'Turno Noite — Pizzaria Bella',
      regiao: 'Centro, Curitiba',
      // ramo do dia da semana (nem hoje nem amanhã)
      dataInicio: hoje.add(const Duration(days: 3, hours: 19)),
      dataFim: hoje.add(const Duration(days: 3, hours: 23)),
      valorEstimado: 145,
      raioEntregaKm: 7,
      status: StatusTurno.aceito,
    ),
  ];
}

/// Turnos do lojista, relativos a [ancora] — mesmo motivo do fakeMeusTurnos.
List<Turno> fakeTurnosLojista({DateTime? ancora}) {
  final hoje = ancora ?? hojeAncorado();
  return [
    Turno(
      id: 301,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Tarde — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      dataInicio: hoje.add(const Duration(days: 1, hours: 14)),
      dataFim: hoje.add(const Duration(days: 1, hours: 18)),
      valorEstimado: 120,
      raioEntregaKm: 8,
      status: StatusTurno.aceito,
    ),
    Turno(
      id: 302,
      lojistId: 2,
      titulo: 'Turno Aberto — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      dataInicio: hoje.add(const Duration(days: 2, hours: 18)),
      dataFim: hoje.add(const Duration(days: 2, hours: 22)),
      valorEstimado: 130,
      raioEntregaKm: 10,
      status: StatusTurno.aberto,
    ),
    Turno(
      id: 303,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Concluído — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      dataInicio: hoje.subtract(const Duration(days: 5)),
      dataFim: hoje.subtract(const Duration(days: 5, hours: -4)),
      valorEstimado: 120,
      raioEntregaKm: 8,
      status: StatusTurno.finalizado,
      pagamentoStatus: PagamentoStatus.pago,
    ),
  ];
}

Map<String, dynamic> fakeDashboardMotoboy() => {
      'score': 4.7,
      'saldoAtual': 320.0,
      'ganhosMensais': 1850.0,
      'turnosFinalizadosMes': 14,
      'turnosFinalizados': 42,
      'mediaAvaliacao': 4.8,
      'ganhosDiarios': [120.0, 95.0, 0.0, 145.0, 110.0, 130.0, 90.0],
      // Chegadas até 10 min após o início, 90 dias (V16).
      'pontualidade': 92,
      'checkinsPontualidade': 13,
    };

Map<String, dynamic> fakeDashboardLojista() => {
      'turnosAtivos': 2,
      'totalGasto': 1500.0,
      'avaliacaoMedia': 4.8,
      'turnosMes': 12,
      'turnosFinalizados': 27,
      'reputacaoEntregadores': 4.7,
    };

/// Carteira com extrato, ancorado em [dataAncoraGolden].
///
/// Antes vinha sem transações, e o golden da carteira mostrava só o estado
/// vazio — ou seja, `_formatarData` ("Hoje, 14:30" / "Ontem, ..." / "12/08,
/// ...") não era exercitado por teste nenhum. Não quebrava, e viraria falha no
/// Um extrato variado, com os tipos que o filtro oferece.
///
/// Cobre os dois lados do dinheiro e os dois casos do sinal: lançamentos com
/// `natureza` gravada (o fluxo novo) e um sem ela (linha anterior à V12), que
/// é o que prova que a tela mostra valor neutro em vez de chutar um lado.
/// Uma NFS-e simulada, do jeito que o backend a devolve.
///
/// [retidos] escolhe a política de tributo: falso (padrão) é o valor
/// aproximado, com líquido igual ao valor do serviço; verdadeiro é a retenção
/// na fonte, com o líquido menor.
/// [papel] é o lado de quem abriu a nota: `prestador` (o entregador, que só
/// vê) ou `tomador` (o lojista, que emite e cancela).
NotaFiscal fakeNotaFiscal({
  bool retidos = false,
  bool cancelada = false,
  String papel = 'prestador',
  bool anoDeTeste = false,
}) {
  const base = 200.0;
  const iss = 10.0;
  const irrf = 3.0;
  return NotaFiscal(
    id: 77,
    turnoId: 202,
    numero: 12,
    serie: 'A1',
    codigoVerificacao: 'A1B2-C3D4',
    prestadorId: 1,
    prestadorNome: 'Ricardo Souza',
    prestadorDocumentoTipo: 'CPF',
    prestadorCidade: 'Curitiba/PR',
    tomadorId: 2,
    tomadorNome: 'Hamburgueria da Cláudia',
    tomadorDocumentoTipo: 'CNPJ',
    tomadorDocumento: '**.345.678/0001-**',
    tomadorCidade: 'Curitiba/PR',
    descricaoServico: 'Serviço de entrega em turno agendado — Turno Noite. '
        'Data: 14/08/2025, das 18:00 às 22:00. Região: Batel, Curitiba.',
    competencia: DateTime(anoDeTeste ? 2026 : 2025, 8, 14, 18),
    valorServico: base,
    issAliquota: 0.05,
    issValor: iss,
    irrfAliquota: 0.015,
    irrfValor: irrf,
    totalTributos: iss + irrf,
    valorLiquido: retidos ? base - iss - irrf : base,
    tributosRetidos: retidos,
    emitidaEm: DateTime(anoDeTeste ? 2026 : 2025, 8, 15, 9, 30),
    canceladaEm: cancelada ? DateTime(2025, 8, 16, 10) : null,
    cancelada: cancelada,
    motivoCancelamento: cancelada ? 'Emitida por engano' : null,
    papel: papel,
    transacaoId: 92,
    operacaoId: '2f1c9c30-0000-4000-8000-000000000001',
    chaveAcesso: anoDeTeste
        ? '41069022100000000000000000000000001226087697394433'
        : '41069022100000000000000000000000001225087697394438',
    danfse: fakeDanfse(retidos: retidos, anoDeTeste: anoDeTeste),
  );
}

/// O DANFSe da nota de [fakeNotaFiscal], como o backend o manda.
///
/// Os JSONs em `test/fixtures` foram gerados pelo próprio `LeiauteDanfse` do
/// backend a partir desta nota: a tela é testada com o que o servidor
/// produz, não com uma cópia escrita à mão. Competência 14/08/2025, sem
/// IBS/CBS; com [anoDeTeste], 14/08/2026 — o ano de teste da reforma, com o
/// quadro de IBS/CBS preenchido (só sem retenção).
Danfse fakeDanfse({bool retidos = false, bool anoDeTeste = false}) {
  final arquivo = File(anoDeTeste
      ? 'test/fixtures/danfse_2026.json'
      : retidos
          ? 'test/fixtures/danfse_com_retencao.json'
          : 'test/fixtures/danfse_sem_retencao.json');
  return Danfse.fromJson(
      jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>);
}

Comprovante fakeComprovante({
  TipoDocumento tipo = TipoDocumento.reciboRecarga,
}) {
  return Comprovante(
    tipo: tipo,
    titulo: tipo.titulo,
    numero: 'RC-00000091',
    codigoAutenticacao: 'AAAA-BBBB-CCCC-DDDD',
    transacaoId: 91,
    operacaoId: null,
    valor: 500,
    credito: true,
    descricao: 'Recarga via Pix',
    dataHora: DateTime(2025, 8, 15, 9),
    titularNome: 'Ricardo Souza',
    titularDocumentoTipo: 'CPF',
    titularCidade: 'Curitiba/PR',
    saldoDisponivelApos: 820,
    detalhes: const [
      LinhaComprovante('Forma de pagamento', 'Pix'),
      LinhaComprovante('Situação', 'Pagamento confirmado'),
      LinhaComprovante('Crédito em', 'Saldo disponível'),
    ],
    valorPorExtenso: 'quinhentos reais',
    fundamento: 'Modelo de quitação do Código Civil, art. 320',
    declaracao: 'Recebemos de Ricardo Souza a importância de R\$ 500,00 '
        '(quinhentos reais), referente à recarga de saldo na carteira '
        'MotoShift, paga via Pix em 15/08/2025 às 09:00, dando por este recibo '
        'plena quitação do valor. Curitiba - PR, 15 de agosto de 2025. '
        'Emitente (credor): MotoShift, em ambiente de simulação — o código de '
        'autenticação abaixo faz as vezes da assinatura.',
  );
}

DocumentoFiscal fakeDocumentoNota({bool retidos = false, bool anoDeTeste = false}) =>
    DocumentoFiscal.daNota(fakeNotaFiscal(retidos: retidos, anoDeTeste: anoDeTeste));

DocumentoFiscal fakeDocumentoComprovante() => DocumentoFiscal(
      tipo: TipoDocumento.reciboRecarga,
      transacaoId: 91,
      marca: DocumentoFiscal.marcaPadrao,
      comprovante: fakeComprovante(),
    );

List<Transacao> fakeExtrato() {
  final dia = DateTime(
      dataAncoraGolden.year, dataAncoraGolden.month, dataAncoraGolden.day);
  return [
    Transacao(
      id: 91,
      motoboyId: 1,
      tipo: TipoTransacao.recarga,
      natureza: NaturezaTransacao.credito,
      valor: 500,
      descricao: 'Recarga via Pix',
      criadoEm: dia.add(const Duration(hours: 9)),
      saldoDisponivelApos: 820,
      // Todo lançamento concluído tem documento; a recarga, um recibo.
      documentoDisponivel: true,
      tipoDocumento: TipoDocumento.reciboRecarga,
    ),
    Transacao(
      id: 92,
      motoboyId: 1,
      contraparteId: 2,
      turnoId: 202,
      tipo: TipoTransacao.pagamentoRecebido,
      natureza: NaturezaTransacao.credito,
      valor: 120,
      descricao: 'Turno finalizado: Hamburgueria da Cláudia',
      // Pagamento de turno: gera NFS-e, e esta já foi emitida (nota 77).
      documentoDisponivel: true,
      tipoDocumento: TipoDocumento.nfse,
      documentoId: 77,
      criadoEm: dia.subtract(const Duration(days: 1, hours: 4)),
      operacaoId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      saldoDisponivelApos: 320,
    ),
    Transacao(
      id: 93,
      motoboyId: 1,
      tipo: TipoTransacao.saque,
      natureza: NaturezaTransacao.debito,
      valor: 200,
      descricao: 'Transferência Pix — ricardo@pix.com',
      criadoEm: dia.subtract(const Duration(days: 2, hours: 3)),
      saldoDisponivelApos: 200,
    ),
    // Sem natureza: linha do histórico, anterior à coluna existir.
    Transacao(
      id: 94,
      motoboyId: 1,
      turnoId: 201,
      tipo: TipoTransacao.desconhecido,
      valor: 45,
      descricao: 'Lançamento antigo sem natureza',
      criadoEm: dia.subtract(const Duration(days: 3, hours: 2)),
    ),
  ];
}

/// O resumo do entregador, como o backend o manda: sem nenhum campo de
/// lojista.
ResumoFinanceiro fakeResumoFinanceiro({double? retencoes}) {
  final dia = DateTime(
      dataAncoraGolden.year, dataAncoraGolden.month, dataAncoraGolden.day);
  return ResumoFinanceiro(
    papel: 'prestador',
    dataInicio: dia.subtract(const Duration(days: 29)),
    dataFim: dia,
    disponivel: 820,
    recebido: 620,
    retencoes: retencoes,
    sacado: 200,
    aReceber: 240,
    porTipo: const [
      TotalPorTipo(
          tipo: TipoTransacao.pagamentoRecebido,
          natureza: NaturezaTransacao.credito,
          total: 620,
          quantidade: 5),
      TotalPorTipo(
          tipo: TipoTransacao.saque,
          natureza: NaturezaTransacao.debito,
          total: 200,
          quantidade: 1),
    ],
  );
}

/// O resumo do lojista: sem recebido, sacado nem a receber.
ResumoFinanceiro fakeResumoLojista() {
  final dia = DateTime(
      dataAncoraGolden.year, dataAncoraGolden.month, dataAncoraGolden.day);
  return ResumoFinanceiro(
    papel: 'tomador',
    dataInicio: dia.subtract(const Duration(days: 29)),
    dataFim: dia,
    disponivel: 820,
    recarregado: 500,
    pagoAEntregadores: 360,
    devolvido: 120,
    bloqueado: 360,
    comprometido: 360,
    reservasAbertas: const [
      ReservaAberta(turnoId: 301, titulo: 'Turno Noite — Hamburgueria', valor: 240),
      ReservaAberta(turnoId: 302, titulo: 'Turno Manhã — Farmácia Ana', valor: 120),
    ],
    porTipo: const [
      TotalPorTipo(
          tipo: TipoTransacao.recarga,
          natureza: NaturezaTransacao.credito,
          total: 500,
          quantidade: 1),
      TotalPorTipo(
          tipo: TipoTransacao.pagamentoEnviado,
          natureza: NaturezaTransacao.debito,
          total: 360,
          quantidade: 3),
    ],
  );
}

List<PontoDeFluxo> fakeFluxo() {
  final dia = DateTime(
      dataAncoraGolden.year, dataAncoraGolden.month, dataAncoraGolden.day);
  return [
    PontoDeFluxo(
        inicio: dia.subtract(const Duration(days: 2)),
        rotulo: '10/08',
        entradas: 0,
        saidas: 200,
        liquido: -200),
    PontoDeFluxo(
        inicio: dia.subtract(const Duration(days: 1)),
        rotulo: '11/08',
        entradas: 120,
        saidas: 0,
        liquido: 120),
    PontoDeFluxo(
        inicio: dia, rotulo: '12/08', entradas: 500, saidas: 0, liquido: 500),
  ];
}

/// dia em que alguém acrescentasse dados aqui.
///
/// Os três lançamentos cobrem os três ramos do formatador, de propósito. As
/// datas são absolutas: com `DateTime.now()` o rótulo "Hoje" viraria "Ontem"
/// à meia-noite e levaria o golden junto.
Carteira fakeCarteira() {
  final dia = DateTime(
      dataAncoraGolden.year, dataAncoraGolden.month, dataAncoraGolden.day);
  return Carteira(
    motoboyId: 1,
    saldoDisponivel: 320,
    ganhosMensais: 1850,
    atualizadoEm: dia.add(const Duration(hours: 14, minutes: 30)),
    transacoes: [
      // ramo "Hoje, HH:mm"
      Transacao(
        id: 1,
        motoboyId: 1,
        turnoId: 202,
        tipo: TipoTransacao.turno,
        valor: 120,
        descricao: 'Turno concluído — Hamburgueria',
        status: StatusTransacao.processado,
        criadoEm: dia.add(const Duration(hours: 14, minutes: 30)),
      ),
      // ramo "Ontem, HH:mm"
      Transacao(
        id: 2,
        motoboyId: 1,
        tipo: TipoTransacao.saque,
        valor: 200,
        descricao: 'Transferência Pix — ricardo@pix.com',
        status: StatusTransacao.concluido,
        criadoEm: dia.subtract(const Duration(days: 1)).add(
              const Duration(hours: 9, minutes: 15),
            ),
      ),
      // ramo "d/MM, HH:mm"
      Transacao(
        id: 3,
        motoboyId: 1,
        turnoId: 201,
        tipo: TipoTransacao.bonus,
        valor: 35,
        descricao: 'Bônus por avaliação 5 estrelas',
        status: StatusTransacao.processado,
        criadoEm: dia.subtract(const Duration(days: 7)).add(
              const Duration(hours: 20),
            ),
      ),
    ],
  );
}

Map<String, dynamic> fakeAvaliacoes() => {
      'mediaGeral': 4.8,
      'totalAvaliacoes': 12,
      'distribuicao': {
        '5estrelas': 8,
        '4estrelas': 3,
        '3estrelas': 1,
        '2estrelas': 0,
        '1estrela': 0,
      },
      'avaliacoes': [
        {
          'turnoId': 1,
          'nota': 5,
          'comentario': 'Ótima organização',
          'nomeAvaliador': 'Cláudia Oliveira',
          'data': '2026-06-15',
        },
        {
          'turnoId': 2,
          'nota': 4,
          'comentario': 'Boa comunicação',
          'nomeAvaliador': 'Ana Souza',
          'data': '2026-06-10',
        },
      ],
    };

/// Notificações fake cobrindo os tipos que a tela 17 estiliza.
List<Map<String, dynamic>> fakeNotificacoes() {
  final agora = clock.now();
  Map<String, dynamic> n(
    int id,
    String tipo,
    String titulo,
    String mensagem,
    bool lida,
    Duration atras,
  ) =>
      {
        'id': id,
        'tipo': tipo,
        'titulo': titulo,
        'mensagem': mensagem,
        'referenciaTipo': 'turno',
        'referenciaId': 101,
        'lida': lida,
        'criadoEm': agora.subtract(atras).toIso8601String(),
      };

  return [
    n(1, 'turno_aceito', 'Turno aceito',
        'Lucas Mendes aceitou Sexta cheia · Rebouças (17:30 – 22:30).',
        false, const Duration(minutes: 12)),
    n(2, 'avaliacao_pendente', 'Avaliação pendente',
        'Avalie Lucas Mendes e Thiago Alves pelo turno de almoço.',
        false, const Duration(hours: 1)),
    n(3, 'pagamento_confirmado', 'Pagamento confirmado',
        'R\$ 130 creditados na sua carteira.', false,
        const Duration(hours: 4)),
    n(4, 'turno_vencendo', 'Turno começa em breve',
        'Seu turno no Batel começa em 1 hora.', false,
        const Duration(hours: 6)),
    n(5, 'turno_expirado', 'Turno expirado',
        'Manhã · Cristo Rei expirou sem entregador.', true,
        const Duration(days: 1)),
    n(6, 'turno_lotado', 'Todas as vagas preenchidas',
        'Sábado · Portão está com as 3 vagas preenchidas.', true,
        const Duration(days: 2)),
  ];
}

Map<String, dynamic> fakeAgendaMensal() => {
      'mes': clock.now().month,
      'ano': clock.now().year,
      'turnos': [],
    };

Map<String, dynamic> fakeAgendaSemanal() => {
      'inicioSemana': clock.now().toIso8601String().substring(0, 10),
      'dias': [],
    };

// ─────────────────────────────────────────────────────────────────────────────
// Fakes das APIs — um por domínio, espelhando services/api/
//
// Antes havia um FakeApiService só, com 30 métodos sobrescritos, porque do
// outro lado havia um ApiService só com 45. Com a API quebrada por domínio, o
// teste passa a poder trocar apenas a parte que exercita: o golden do
// histórico troca o TurnoApi e herda o resto.
// ─────────────────────────────────────────────────────────────────────────────

class FakeAuthApi extends AuthApi {
  FakeAuthApi() : super(ApiClient());

  // Senha (SCRUM-32): por padrão tudo dá certo, sem rede. O teste que quer
  // ver o erro sobrescreve.
  @override
  Future<void> trocarSenha({
    required String senhaAtual,
    required String senhaNova,
  }) async {}

  @override
  Future<void> esqueciSenha(String email) async {}

  @override
  Future<void> redefinirSenha({
    required String email,
    required String codigo,
    required String senhaNova,
  }) async {}

  @override
  Future<Usuario> buscarUsuario(int id) async => fakeMotoboy();

  @override
  Future<Usuario> atualizarUsuario(Usuario usuario) async => usuario;

  @override
  Future<Usuario> atualizarPerfil(int id, Map<String, dynamic> campos) async =>
      fakeMotoboy();
}

class FakeTurnoApi extends TurnoApi {
  FakeTurnoApi() : super(ApiClient());

  @override
  Future<List<Turno>> listarTurnosDisponiveis({DateTime? data}) async =>
      fakeTurnosDisponiveis();

  /// Qualquer turno dos fakes, pelo id — é o que a notificação usa para
  /// montar o destino.
  @override
  Future<Turno> buscarTurno(int turnoId) async {
    final todos = [
      ...fakeTurnosDisponiveis(),
      ...fakeMeusTurnos(),
      ...fakeTurnosLojista(),
    ];
    for (final t in todos) {
      if (t.id == turnoId) return t;
    }
    throw const ApiException(404, 'Turno não encontrado.');
  }

  /// Um inscrito por turno: o entregador dos fakes.
  ///
  /// Sem este override a tela do lojista cairia no `catch` de
  /// `_sincronizarInscritos`, que tenta a rede de verdade — e o card do
  /// entregador só apareceria depois de o socket desistir, ou seja, nunca
  /// dentro de um golden.
  @override
  Future<List<Map<String, dynamic>>> listarInscritos(int turnoId) async => [
        {
          'motoboyId': 1,
          'nome': 'Ricardo Souza',
          'status': 'ACEITO',
          'pagamentoStatus': 'PAGO',
        },
      ];

  @override
  Future<List<Turno>> listarTurnosLojista(int lojistId) async =>
      fakeTurnosLojista();

  @override
  Future<List<Turno>> listarMeusTurnos(int motoboyId) async => fakeMeusTurnos();

  @override
  Future<List<Turno>> listarTurnosDisponiveisComFiltros({
    String? horarioInicio,
    String? horarioFim,
    int? diaSemana,
    double? raioMaxKm,
    String? dataInicio,
    String? dataFim,
    String? ordenarPor,
    double? lat,
    double? lng,
    double? raioKm,
  }) async =>
      fakeTurnosDisponiveis();
}

/// Carteira falsa, com o extrato filtrado no próprio fake.
///
/// O filtro é aplicado aqui, e não ignorado, porque é exatamente o que o teste
/// de extrato precisa verificar: que a tela manda o filtro certo e desenha o
/// que voltou. Um fake que devolvesse tudo faria o teste passar mesmo se a tela
/// parasse de filtrar.
class FakeCarteiraApi extends CarteiraApi {
  FakeCarteiraApi({this.papel = TipoUsuario.motoboy}) : super(ApiClient());

  /// De quem é a carteira: o resumo do backend depende do papel.
  final TipoUsuario papel;

  /// Registro do que a tela pediu — para o teste conferir o filtro enviado.
  final List<ExtratoFiltro> filtrosRecebidos = [];

  /// Cobranças criadas, para o teste de recarga acompanhar o fluxo.
  final List<Cobranca> recargasCriadas = [];
  final List<int> confirmacoes = [];

  int _proximaCobranca = 900;

  /// Documentos gerados pela tela — o teste confere qual lançamento foi pedido.
  final List<int> documentosGerados = [];

  /// Documentos só consultados (GET). A NFS-e do entregador tem de vir por
  /// aqui: quem emite é o lojista.
  final List<int> documentosBuscados = [];

  @override
  Future<Carteira> buscarCarteira(int motoboyId) async => fakeCarteira();

  @override
  Future<DocumentoFiscal> gerarDocumento(int transacaoId) async {
    documentosGerados.add(transacaoId);
    return _documentoDe(transacaoId);
  }

  @override
  Future<DocumentoFiscal> buscarDocumento(int transacaoId) async {
    documentosBuscados.add(transacaoId);
    return _documentoDe(transacaoId);
  }

  /// A regra do backend em miniatura: pagamento de turno vira NFS-e, o resto
  /// vira comprovante.
  DocumentoFiscal _documentoDe(int transacaoId) {
    final lancamento = fakeExtrato().where((t) => t.id == transacaoId).firstOrNull;
    return lancamento?.tipoDocumento == TipoDocumento.nfse
        ? fakeDocumentoNota()
        : fakeDocumentoComprovante();
  }

  /// Filtros pedidos na exportação em lista (a base do PDF).
  final List<ExtratoFiltro> exportacoesEmLista = [];

  @override
  Future<List<Transacao>> exportarExtratoLista({
    ExtratoFiltro filtro = const ExtratoFiltro(),
  }) async {
    exportacoesEmLista.add(filtro);
    return _filtrar(filtro);
  }

  @override
  Future<PaginaDoExtrato> buscarExtrato({
    ExtratoFiltro filtro = const ExtratoFiltro(),
    int pagina = 0,
    int tamanho = 20,
  }) async {
    filtrosRecebidos.add(filtro);

    final filtrados = _filtrar(filtro);

    final de = pagina * tamanho;
    final ate = (de + tamanho).clamp(0, filtrados.length);
    return (
      itens: de >= filtrados.length ? <Transacao>[] : filtrados.sublist(de, ate),
      total: filtrados.length,
    );
  }

  List<Transacao> _filtrar(ExtratoFiltro filtro) {
    final todos = fakeExtrato();
    return todos.where((t) {
      if (filtro.tipos.isNotEmpty && !filtro.tipos.contains(t.tipo)) {
        return false;
      }
      if (filtro.natureza != null && t.natureza != filtro.natureza) {
        return false;
      }
      if (filtro.busca != null && filtro.busca!.isNotEmpty) {
        if (!t.descricao.toLowerCase().contains(filtro.busca!.toLowerCase())) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Future<ResumoFinanceiro> buscarResumo({
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async =>
      papel == TipoUsuario.lojista ? fakeResumoLojista() : fakeResumoFinanceiro();

  @override
  Future<List<PontoDeFluxo>> buscarFluxo({
    String agrupamento = 'dia',
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async =>
      fakeFluxo();

  @override
  Future<String> exportarExtratoCsv({
    ExtratoFiltro filtro = const ExtratoFiltro(),
  }) async =>
      'data;tipo;valor\n01/09/2026 12:00;recarga;500.00\n';

  @override
  Future<Cobranca> criarRecarga(double valor) async {
    final c = Cobranca(
      id: _proximaCobranca++,
      tipo: TipoCobranca.recarga,
      valor: valor,
      status: StatusCobranca.pendente,
      codigoPix: '00020126580014BR.GOV.BCB.PIX0136motoshift-demo-fake',
      criadaEm: dataAncoraGolden,
    );
    recargasCriadas.add(c);
    return c;
  }

  @override
  Future<Cobranca> confirmarRecarga(int cobrancaId) async {
    confirmacoes.add(cobrancaId);
    final pendente = recargasCriadas.firstWhere((c) => c.id == cobrancaId);
    return Cobranca(
      id: pendente.id,
      tipo: pendente.tipo,
      valor: pendente.valor,
      status: StatusCobranca.concluido,
      codigoPix: pendente.codigoPix,
      criadaEm: pendente.criadaEm,
      concluidaEm: dataAncoraGolden,
    );
  }

  @override
  Future<Cobranca> solicitarSaque(double valor) async => Cobranca(
        id: _proximaCobranca++,
        tipo: TipoCobranca.saque,
        valor: valor,
        status: StatusCobranca.concluido,
        codigoPix: 'entregador@pix.com',
        criadaEm: dataAncoraGolden,
        concluidaEm: dataAncoraGolden,
      );

  @override
  Future<List<Map<String, dynamic>>> buscarGrafico(int motoboyId,
          {int meses = 6}) async =>
      [
        {'mes': 'Jan', 'valor': 800.0},
        {'mes': 'Fev', 'valor': 950.0},
        {'mes': 'Mar', 'valor': 1100.0},
        {'mes': 'Abr', 'valor': 1500.0},
        {'mes': 'Mai', 'valor': 1750.0},
        {'mes': 'Jun', 'valor': 1850.0},
      ];
}

class FakeDashboardApi extends DashboardApi {
  FakeDashboardApi() : super(ApiClient());

  @override
  Future<Map<String, dynamic>> dashboardMotoboy(int motoboyId) async =>
      fakeDashboardMotoboy();

  @override
  Future<Map<String, dynamic>> dashboardLojista(int lojistId) async =>
      fakeDashboardLojista();
}

class FakeAgendaApi extends AgendaApi {
  FakeAgendaApi() : super(ApiClient());

  @override
  Future<Map<String, dynamic>> buscarAgendaMensal(
          int usuarioId, int mes, int ano) async =>
      fakeAgendaMensal();

  @override
  Future<Map<String, dynamic>> buscarAgendaSemanal(
          int usuarioId, String data) async =>
      fakeAgendaSemanal();
}

class FakeAvaliacaoApi extends AvaliacaoApi {
  FakeAvaliacaoApi() : super(ApiClient());

  @override
  Future<Map<String, dynamic>> buscarAvaliacoes(int usuarioId) async =>
      fakeAvaliacoes();

  @override
  Future<List<int>> buscarTurnosAvaliados(int usuarioId) async => [1, 2];

  /// Turnos 1 e 2 já avaliados; os demais ainda devem uma nota.
  ///
  /// É a mesma seleção de [buscarTurnosAvaliados], agora expressa do lado
  /// certo: a tela pergunta "quem falta neste turno", e não "quais turnos já
  /// toquei". Um pendente por turno — o caso multi-vaga tem fake próprio,
  /// em `avaliacao_multivaga_test.dart`.
  static const _jaAvaliados = {1, 2};

  @override
  Future<bool> verificarPendente(int turnoId, int usuarioId) async =>
      !_jaAvaliados.contains(turnoId);

  @override
  Future<({bool precisaAvaliar, List<Map<String, dynamic>> pendentes})>
      buscarAvaliacoesPendentes(int turnoId, int usuarioId) async {
    if (_jaAvaliados.contains(turnoId)) {
      return (precisaAvaliar: false, pendentes: <Map<String, dynamic>>[]);
    }
    // A outra parte do turno: o lojista (id 2) deve nota ao entregador, e o
    // entregador (id 1) à loja.
    final contraparte = usuarioId == 2
        ? {'usuarioId': 1, 'nome': 'Ricardo Souza'}
        : {'usuarioId': 2, 'nome': 'Cláudia Oliveira'};
    return (
      precisaAvaliar: true,
      pendentes: <Map<String, dynamic>>[contraparte],
    );
  }
}

/// Favoritos do lojista em memória (V18). Começa com o Ricardo — o
/// entregador de [fakeMotoboy] —, para o perfil do lojista mostrar a lista.
class FakeFavoritoApi extends FavoritoApi {
  FakeFavoritoApi({List<EntregadorFavorito>? iniciais})
      : lista = iniciais ??
            [
              const EntregadorFavorito(
                  motoboyId: 1,
                  nome: 'Ricardo Souza',
                  mediaAvaliacao: 4.8,
                  score: 4.7),
            ],
        super(ApiClient());

  final List<EntregadorFavorito> lista;

  @override
  Future<List<EntregadorFavorito>> listar() async => List.of(lista);

  @override
  Future<EntregadorFavorito> favoritar(int motoboyId) async {
    final existente = lista.where((f) => f.motoboyId == motoboyId).firstOrNull;
    if (existente != null) return existente;
    final novo = EntregadorFavorito(
        motoboyId: motoboyId, nome: 'Entregador $motoboyId');
    lista.insert(0, novo);
    return novo;
  }

  @override
  Future<void> desfavoritar(int motoboyId) async =>
      lista.removeWhere((f) => f.motoboyId == motoboyId);
}

class FakeNotificacaoApi extends NotificacaoApi {
  FakeNotificacaoApi() : super(ApiClient());

  @override
  Future<int> contarNotificacoesNaoLidas(int usuarioId) async =>
      fakeNotificacoes().where((n) => n['lida'] == false).length;

  @override
  Future<List<Map<String, dynamic>>> listarNotificacoes(
    int usuarioId, {
    bool apenasNaoLidas = false,
  }) async {
    final todas = fakeNotificacoes();
    if (!apenasNaoLidas) return todas;
    return todas.where((n) => n['lida'] == false).toList();
  }
}

/// Notas fiscais vazias.
///
/// Sem fake, `pendentes()` saía para a rede de verdade — o mock de HTTP dos
/// testes não responde, e cada chamada esperava o timeout do ApiClient. O
/// PendenciasProvider consulta as notas a cada carregamento, então todo
/// teste que tocasse o menu pagava ~20 s por isso.
/// Notas fiscais falsas, com memória do que a tela pediu.
///
/// Guarda [ultimoFiltro] porque é isso que os testes de filtro precisam
/// prender: a tela manda o filtro à API, em vez de baixar tudo e peneirar na
/// memória — o contrário volta a crescer sem limite com o tempo de uso.
class FakeNotaFiscalApi extends NotaFiscalApi {
  FakeNotaFiscalApi() : super(ApiClient());

  NotaFiscalFiltro? ultimoFiltro;
  int? ultimaPagina;
  int? ultimoTamanho;
  int? anoPedidoNoResumo;
  int exportacoesDoResumo = 0;

  /// A lista e o total são independentes de propósito: assim um teste pede
  /// "2 de 7" e vê o botão de carregar mais.
  List<NotaFiscal> notas = const [];
  int total = 0;
  List<NotaFiscalPendente> listaPendentes = const [];
  InformeAnual informe = fakeInformeAnual();

  @override
  Future<PaginaDeNotas> listar({
    NotaFiscalFiltro filtro = const NotaFiscalFiltro(),
    int? pagina,
    int tamanho = 20,
  }) async {
    ultimoFiltro = filtro;
    ultimaPagina = pagina;
    ultimoTamanho = tamanho;
    return PaginaDeNotas(notas: notas.take(tamanho).toList(), total: total);
  }

  @override
  Future<InformeAnual> resumo({int? ano}) async {
    anoPedidoNoResumo = ano;
    return informe;
  }

  @override
  Future<String> exportarResumo({int? ano}) async {
    exportacoesDoResumo++;
    return 'ano;total\n$ano;1200,00\n';
  }

  @override
  Future<List<NotaFiscalPendente>> pendentes() async => listaPendentes;
}

/// Informe anual falso: dois meses com movimento, duas fontes pagadoras e um
/// pagamento ainda sem nota — o caso que a tela precisa saber contar.
InformeAnual fakeInformeAnual({
  int? ano,
  String papel = 'prestador',
  bool retido = false,
}) {
  return InformeAnual(
    ano: ano ?? DateTime.now().year,
    papel: papel,
    titulo: papel == 'prestador'
        ? 'Informe de rendimentos'
        : 'Informe de serviços tomados',
    total: 1200,
    issRetido: retido ? 60 : 0,
    irrfRetido: retido ? 18 : 0,
    pagamentos: 6,
    notasEmitidas: 5,
    contrapartes: [
      const ContraparteDoInforme(
        contraparteId: 2,
        nome: 'Hamburgueria da Cláudia',
        documentoTipo: 'CNPJ',
        documento: '**.345.678/0001-**',
        total: 800,
        issRetido: 0,
        irrfRetido: 0,
        pagamentos: 4,
        notasEmitidas: 4,
      ),
      const ContraparteDoInforme(
        contraparteId: 5,
        nome: 'Pizzaria do Bairro',
        documentoTipo: 'CNPJ',
        total: 400,
        issRetido: 0,
        irrfRetido: 0,
        pagamentos: 2,
        notasEmitidas: 1,
      ),
    ],
    meses: [
      for (var m = 1; m <= 12; m++)
        MesDoInforme(
          mes: m,
          total: m == 8 ? 800 : (m == 9 ? 400 : 0),
          pagamentos: m == 8 ? 4 : (m == 9 ? 2 : 0),
        ),
    ],
    marca: 'DOCUMENTO SIMULADO — SEM VALOR FISCAL',
  );
}


/// Perfil público de outra conta. Devolve o fake do papel pedido — id 2 é a
/// lojista, qualquer outro é o entregador.
class FakeUsuarioApi extends UsuarioApi {
  FakeUsuarioApi() : super(ApiClient());

  @override
  Future<PerfilPublico> buscarPerfilPublico(int usuarioId) async {
    final u = usuarioId == 2 ? fakeLojista() : fakeMotoboy();
    return PerfilPublico(
      id: u.id!,
      nome: u.nome,
      tipo: u.tipo.name,
      cidade: u.cidade,
      estado: u.estado,
      score: u.score,
      mediaAvaliacao: u.mediaAvaliacao,
      veiculoModelo: u.veiculoModelo,
      veiculoCor: u.veiculoCor,
      nomeFantasia: u.nomeFantasia,
    );
  }
}

/// O ApiService dos testes: mesma montagem do de produção, com cada domínio
/// trocado pelo seu fake.
class FakeApiService extends ApiService {
  /// [tipoUsuario] é o papel da conta logada — o fake da carteira devolve o
  /// resumo daquele papel, como o backend faz.
  FakeApiService({
    TipoUsuario tipoUsuario = TipoUsuario.motoboy,
    bool resultadoComPrejuizo = false,
  })  : _carteira = FakeCarteiraApi(papel: tipoUsuario),
        _financeiro = FakeFinanceiroApi(
            papel: tipoUsuario, comPrejuizo: resultadoComPrejuizo);

  @override
  FinanceiroApi get financeiro => _financeiro;
  final FinanceiroApi _financeiro;

  @override
  AuthApi get auth => _auth;
  final AuthApi _auth = FakeAuthApi();

  @override
  TurnoApi get turnos => _turnos;
  final TurnoApi _turnos = FakeTurnoApi();

  @override
  UsuarioApi get usuarios => _usuarios;
  final UsuarioApi _usuarios = FakeUsuarioApi();

  @override
  NotaFiscalApi get notasFiscais => _notasFiscais;
  final NotaFiscalApi _notasFiscais = FakeNotaFiscalApi();

  @override
  CarteiraApi get carteira => _carteira;
  final CarteiraApi _carteira;

  @override
  DashboardApi get dashboard => _dashboard;
  final DashboardApi _dashboard = FakeDashboardApi();

  @override
  AgendaApi get agenda => _agenda;
  final AgendaApi _agenda = FakeAgendaApi();

  @override
  AvaliacaoApi get avaliacoes => _avaliacoes;
  final AvaliacaoApi _avaliacoes = FakeAvaliacaoApi();

  @override
  NotificacaoApi get notificacoes => _notificacoes;
  final NotificacaoApi _notificacoes = FakeNotificacaoApi();

  @override
  FavoritoApi get favoritos => _favoritos;
  final FavoritoApi _favoritos = FakeFavoritoApi();

  @override
  StatusApi get status => statusFalso;

  /// O `/api/status` desta API. Por padrão o servidor está no ar; o teste da
  /// espera o põe para dormir com `statusFalso.dormindo = true`.
  final FakeStatusApi statusFalso = FakeStatusApi();
}

/// O `/api/status` dos testes (SCRUM-48).
///
/// Responde na hora, sem rede: para todas as telas o servidor está no ar, e
/// a faixa "Acordando o servidor…" nunca aparece. Com [dormindo], nenhuma
/// pergunta é respondida até [acordar] — o servidor do plano gratuito depois
/// de 15 minutos parado.
class FakeStatusApi extends StatusApi {
  FakeStatusApi({this.dormindo = false}) : super(ApiClient());

  bool dormindo;

  /// Quantas vezes o app perguntou.
  int perguntas = 0;

  final List<Completer<bool>> _semResposta = [];

  @override
  Future<bool> noAr() {
    perguntas++;
    if (!dormindo) return Future.value(true);
    final pergunta = Completer<bool>();
    _semResposta.add(pergunta);
    return pergunta.future;
  }

  /// O servidor acordou: as perguntas que estavam no ar são respondidas, e as
  /// próximas também.
  void acordar() {
    dormindo = false;
    for (final pergunta in _semResposta) {
      pergunta.complete(true);
    }
    _semResposta.clear();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Resultado (RF13): a DRE e os lançamentos gerenciais, ancorados em
// [dataAncoraGolden] (agosto de 2026). Os números são os do Carlos e da
// Cláudia da massa de demonstração, arredondados.
// ─────────────────────────────────────────────────────────────────────────────

/// A DRE do entregador em agosto: com [comPrejuizo], entra a manutenção de
/// R$ 420 — o mês em que a moto custou mais do que rendeu.
Dre fakeDreEntregador({bool comPrejuizo = false}) {
  final manutencao = comPrejuizo ? 420.0 : 0.0;
  final resultado = 111.95 - manutencao;
  LinhaDre manual(String chave, String rotulo, double valor) => LinhaDre(
      chave: chave, rotulo: rotulo, valor: valor, origem: OrigemDaLinha.manual, subtrai: true);
  LinhaDre subtotal(String chave, String rotulo, double valor) =>
      LinhaDre(chave: chave, rotulo: rotulo, valor: valor, tipo: TipoDeLinhaDre.subtotal);

  return Dre(
    papel: TipoUsuario.motoboy,
    dataInicio: DateTime(2026, 8, 1),
    dataFim: DateTime(2026, 8, 19),
    linhas: [
      const LinhaDre(
          chave: 'pagamentos_recebidos',
          rotulo: 'Pagamentos de turnos',
          valor: 380,
          origem: OrigemDaLinha.extrato),
      const LinhaDre(
          chave: 'gorjetas_recebidas',
          rotulo: 'Gorjetas',
          valor: 10,
          origem: OrigemDaLinha.extrato),
      subtotal('receita_bruta', 'Receita bruta', 390),
      const LinhaDre(
          chave: 'retencoes_na_fonte',
          rotulo: 'Retenções na fonte (ISS e IRRF)',
          valor: 0,
          origem: OrigemDaLinha.extrato,
          subtrai: true),
      manual('das_mei', 'DAS do MEI', 86.05),
      subtotal('receita_liquida', 'Receita líquida', 303.95),
      manual('combustivel', 'Combustível', 30),
      manual('manutencao', 'Manutenção', manutencao),
      subtotal('margem_de_contribuicao', 'Margem de contribuição', 273.95 - manutencao),
      manual('celular_internet', 'Celular e internet', 35),
      manual('seguro', 'Seguro', 32),
      manual('parcela_ou_aluguel_veiculo', 'Parcela ou aluguel do veículo', 95),
      manual('outra_despesa_entregador', 'Outra despesa', 0),
      LinhaDre(
          chave: 'resultado',
          rotulo: 'Resultado do período',
          valor: resultado,
          tipo: TipoDeLinhaDre.resultado),
    ],
    resultado: resultado,
    situacao: comPrejuizo ? SituacaoDre.prejuizo : SituacaoDre.lucro,
    indicadores: {
      'margemLiquida': comPrejuizo ? -78.99 : 28.71,
      'turnosPagos': 4,
      'horasTrabalhadas': 16.0,
      'lucroPorHora': comPrejuizo ? -19.25 : 7.0,
      'lucroPorTurno': comPrejuizo ? -77.01 : 27.99,
      'kmInformados': 168.0,
      'custoPorKm': comPrejuizo ? 2.68 : 0.18,
      'margemDeContribuicaoPorTurno': comPrejuizo ? -36.51 : 68.49,
      'pontoDeEquilibrioTurnos': comPrejuizo ? null : 3,
      'pontoDeEquilibrioMotivo':
          comPrejuizo ? 'a margem por turno não cobre os custos variáveis' : null,
    },
    anterior: DreAnterior(
      dataInicio: DateTime(2026, 7, 13),
      dataFim: DateTime(2026, 7, 31),
      resultado: comPrejuizo ? 97.0 : -205.55,
      situacao: comPrejuizo ? SituacaoDre.lucro : SituacaoDre.prejuizo,
    ),
    variacaoResultado: comPrejuizo ? resultado - 97.0 : resultado + 205.55,
    lancamentosManuais: comPrejuizo ? 9 : 8,
  );
}

/// A DRE da operação de entrega da loja em agosto: as taxas cobradas cobrem
/// os entregadores.
Dre fakeDreLojista() {
  return Dre(
    papel: TipoUsuario.lojista,
    dataInicio: DateTime(2026, 8, 1),
    dataFim: DateTime(2026, 8, 19),
    linhas: const [
      LinhaDre(
          chave: 'receita_de_entregas',
          rotulo: 'Receita de entregas (taxas cobradas)',
          valor: 832,
          origem: OrigemDaLinha.manual),
      LinhaDre(
          chave: 'custo_dos_entregadores',
          rotulo: 'Pagamentos e gorjetas a entregadores',
          valor: 530,
          origem: OrigemDaLinha.extrato,
          subtrai: true),
      LinhaDre(
          chave: 'entrega_fora_do_app',
          rotulo: 'Entrega fora do app',
          valor: 45,
          origem: OrigemDaLinha.manual,
          subtrai: true),
      LinhaDre(
          chave: 'margem_da_operacao',
          rotulo: 'Margem da operação',
          valor: 257,
          tipo: TipoDeLinhaDre.subtotal),
      LinhaDre(
          chave: 'outra_despesa_entrega',
          rotulo: 'Outra despesa de entrega',
          valor: 60,
          origem: OrigemDaLinha.manual,
          subtrai: true),
      LinhaDre(
          chave: 'resultado',
          rotulo: 'Resultado da operação de entrega',
          valor: 197,
          tipo: TipoDeLinhaDre.resultado),
    ],
    resultado: 197,
    situacao: SituacaoDre.lucro,
    indicadores: const {
      'custoSobreReceita': 69.11,
      'turnosFinalizados': 4,
      'custoMedioPorTurno': 132.5,
      'resultadoPorTurno': 49.25,
      'gorjetasDadas': 10.0,
    },
    anterior: DreAnterior(
      dataInicio: DateTime(2026, 7, 13),
      dataFim: DateTime(2026, 7, 31),
      resultado: -290,
      situacao: SituacaoDre.prejuizo,
    ),
    variacaoResultado: 487,
    lancamentosManuais: 6,
  );
}

/// Os doze meses de 2026: movimento de abril a agosto, um mês de prejuízo.
List<MesDre> fakeMesesDaDre({bool lojista = false, bool agostoComPrejuizo = false}) {
  const rotulos = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
  // (receita, custos) de abril a agosto.
  final movimento = lojista
      ? const {4: (832.0, 590.0), 5: (1040.0, 700.0), 6: (832.0, 560.0), 7: (240.0, 530.0), 8: (832.0, 635.0)}
      : {
          4: (380.0, 278.05),
          5: (475.0, 285.55),
          6: (385.0, 323.05),
          7: (380.0, 698.05),
          8: (390.0, agostoComPrejuizo ? 698.05 : 278.05),
        };
  return [
    for (var m = 1; m <= 12; m++)
      MesDre(
        mes: m,
        rotulo: rotulos[m - 1],
        receita: movimento[m]?.$1 ?? 0,
        custos: movimento[m]?.$2 ?? 0,
        resultado: (movimento[m]?.$1 ?? 0) - (movimento[m]?.$2 ?? 0),
      ),
  ];
}

List<CategoriaDeLancamento> fakeCategoriasDeLancamento(TipoUsuario papel) {
  CategoriaDeLancamento c(String valor, String rotulo, String grupo, String rotuloDoGrupo,
          {bool soma = false}) =>
      CategoriaDeLancamento(
          valor: valor, rotulo: rotulo, grupo: grupo, rotuloDoGrupo: rotuloDoGrupo, soma: soma);
  return papel == TipoUsuario.lojista
      ? [
          c('taxa_de_entrega_cobrada', 'Taxa de entrega cobrada', 'receita', 'Receita', soma: true),
          c('entrega_fora_do_app', 'Entrega fora do app', 'custo_entrega', 'Custo de entrega'),
          c('outra_despesa_entrega', 'Outra despesa de entrega', 'despesa_operacional',
              'Outras despesas'),
        ]
      : [
          c('combustivel', 'Combustível', 'custo_variavel', 'Custos variáveis'),
          c('manutencao', 'Manutenção', 'custo_variavel', 'Custos variáveis'),
          c('das_mei', 'DAS do MEI', 'deducao', 'Deduções'),
          c('celular_internet', 'Celular e internet', 'despesa_fixa', 'Despesas fixas'),
          c('seguro', 'Seguro', 'despesa_fixa', 'Despesas fixas'),
          c('parcela_ou_aluguel_veiculo', 'Parcela ou aluguel do veículo', 'despesa_fixa',
              'Despesas fixas'),
          c('outra_despesa_entregador', 'Outra despesa', 'despesa_fixa', 'Despesas fixas'),
        ];
}

List<LancamentoGerencial> fakeLancamentosGerenciais(TipoUsuario papel, {bool comPrejuizo = false}) {
  if (papel == TipoUsuario.lojista) {
    return [
      LancamentoGerencial(
          id: 31,
          categoria: 'taxa_de_entrega_cobrada',
          rotuloDaCategoria: 'Taxa de entrega cobrada',
          soma: true,
          valor: 208,
          data: DateTime(2026, 8, 15),
          turnoId: 7,
          descricao: 'Taxas de entrega cobradas na noite',
          ocorrenciasNoPeriodo: 1,
          valorNoPeriodo: 208),
      LancamentoGerencial(
          id: 32,
          categoria: 'entrega_fora_do_app',
          rotuloDaCategoria: 'Entrega fora do app',
          valor: 45,
          data: DateTime(2026, 8, 14),
          descricao: 'Motoboy avulso numa noite de chuva',
          ocorrenciasNoPeriodo: 1,
          valorNoPeriodo: 45),
      LancamentoGerencial(
          id: 33,
          categoria: 'outra_despesa_entrega',
          rotuloDaCategoria: 'Outra despesa de entrega',
          valor: 60,
          data: DateTime(2026, 8, 3),
          descricao: 'Embalagens térmicas e mochila reserva',
          ocorrenciasNoPeriodo: 1,
          valorNoPeriodo: 60),
    ];
  }
  return [
    if (comPrejuizo)
      LancamentoGerencial(
          id: 25,
          categoria: 'manutencao',
          rotuloDaCategoria: 'Manutenção',
          valor: 420,
          data: DateTime(2026, 8, 12),
          descricao: 'Troca da relação, do pneu traseiro e das pastilhas',
          ocorrenciasNoPeriodo: 1,
          valorNoPeriodo: 420),
    LancamentoGerencial(
        id: 21,
        categoria: 'combustivel',
        rotuloDaCategoria: 'Combustível',
        valor: 7.5,
        data: DateTime(2026, 8, 12),
        turnoId: 4,
        km: 42,
        descricao: 'Gasolina do turno',
        ocorrenciasNoPeriodo: 1,
        valorNoPeriodo: 7.5),
    LancamentoGerencial(
        id: 22,
        categoria: 'das_mei',
        rotuloDaCategoria: 'DAS do MEI',
        valor: 86.05,
        data: DateTime(2026, 8, 10),
        descricao: 'DAS do MEI de 07/2026',
        ocorrenciasNoPeriodo: 1,
        valorNoPeriodo: 86.05),
    LancamentoGerencial(
        id: 23,
        categoria: 'parcela_ou_aluguel_veiculo',
        rotuloDaCategoria: 'Parcela ou aluguel do veículo',
        valor: 95,
        data: DateTime(2026, 4, 5),
        recorrente: true,
        descricao: 'Parcela do consórcio da moto',
        ocorrenciasNoPeriodo: 1,
        valorNoPeriodo: 95),
    LancamentoGerencial(
        id: 24,
        categoria: 'seguro',
        rotuloDaCategoria: 'Seguro',
        valor: 32,
        data: DateTime(2026, 4, 15),
        recorrente: true,
        descricao: 'Seguro contra roubo (rateio da associação)',
        ocorrenciasNoPeriodo: 1,
        valorNoPeriodo: 32),
  ];
}

/// O backend do resultado, sem rede: devolve as fixtures acima e anota o que
/// a tela pediu e mandou.
class FakeFinanceiroApi extends FinanceiroApi {
  FakeFinanceiroApi({
    this.papel = TipoUsuario.motoboy,
    this.comPrejuizo = false,
    this.semLancamentos = false,
    this.erroAoSalvar,
    this.erroNaDre,
  }) : super(ApiClient());

  final TipoUsuario papel;
  final bool comPrejuizo;

  /// A conta de quem ainda não informou nada: DRE só com o extrato.
  final bool semLancamentos;
  final ApiException? erroAoSalvar;

  /// A DRE fora do ar — para o painel, que tem de continuar de pé sem ela.
  final ApiException? erroNaDre;

  /// Os períodos pedidos, na ordem.
  final List<(DateTime?, DateTime?)> periodosPedidos = [];
  final List<int?> anosPedidos = [];
  final List<LancamentoGerencial> criados = [];
  final List<(int, LancamentoGerencial)> atualizados = [];

  /// O `aplicarAPartirDe` de cada edição, na ordem: nulo quando a edição
  /// corrige o histórico inteiro.
  final List<DateTime?> alcancesDasEdicoes = [];
  final List<int> excluidos = [];

  @override
  Future<Dre> buscarDre({DateTime? dataInicio, DateTime? dataFim}) async {
    if (erroNaDre != null) throw erroNaDre!;
    periodosPedidos.add((dataInicio, dataFim));
    final base = papel == TipoUsuario.lojista
        ? fakeDreLojista()
        : fakeDreEntregador(comPrejuizo: comPrejuizo);
    return Dre(
      papel: base.papel,
      // A tela mostra o período que pediu.
      dataInicio: dataInicio ?? base.dataInicio,
      dataFim: dataFim ?? base.dataFim,
      linhas: base.linhas,
      resultado: base.resultado,
      situacao: base.situacao,
      indicadores: base.indicadores,
      anterior: base.anterior,
      variacaoResultado: base.variacaoResultado,
      lancamentosManuais: semLancamentos ? 0 : base.lancamentosManuais,
    );
  }

  @override
  Future<List<MesDre>> buscarDreMensal({int? ano}) async {
    anosPedidos.add(ano);
    if (ano != null && ano != 2026) return fakeMesesDaDre().map(_zerado).toList();
    return fakeMesesDaDre(
        lojista: papel == TipoUsuario.lojista, agostoComPrejuizo: comPrejuizo);
  }

  static MesDre _zerado(MesDre m) =>
      MesDre(mes: m.mes, rotulo: m.rotulo, receita: 0, custos: 0, resultado: 0);

  @override
  Future<List<CategoriaDeLancamento>> buscarCategorias() async =>
      fakeCategoriasDeLancamento(papel);

  @override
  Future<List<LancamentoGerencial>> listarLancamentos({
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async =>
      semLancamentos ? const [] : fakeLancamentosGerenciais(papel, comPrejuizo: comPrejuizo);

  @override
  Future<LancamentoGerencial> criarLancamento(LancamentoGerencial l) async {
    if (erroAoSalvar != null) throw erroAoSalvar!;
    criados.add(l);
    return l;
  }

  @override
  Future<LancamentoGerencial> atualizarLancamento(
    int id,
    LancamentoGerencial l, {
    DateTime? aplicarAPartirDe,
  }) async {
    if (erroAoSalvar != null) throw erroAoSalvar!;
    atualizados.add((id, l));
    alcancesDasEdicoes.add(aplicarAPartirDe);
    return l;
  }

  @override
  Future<void> excluirLancamento(int id) async {
    excluidos.add(id);
  }
}

/// Turnos encerrados com data ABSOLUTA, para as telas de histórico.
///
/// Os demais fakes se ancoram em `hojeAncorado()` de propósito: as telas de
/// turno filtram por "ainda vai acontecer", e isso só funciona com datas
/// relativas a hoje. O histórico é o oposto — ele só mostra turnos encerrados
/// e imprime a data em dd/MM/yyyy. Com fixture relativa, o golden dele mudaria
/// de dia junto com o calendário e a suíte amanheceria vermelha sozinha.
List<Turno> fakeTurnosEncerradosFixos() {
  final base = DateTime(2026, 8, 19); // mesmo dia do dataAncoraGolden
  return [
    Turno(
      id: 401,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Concluído — pendente pagamento',
      regiao: 'Água Verde, Curitiba',
      dataInicio: base.subtract(const Duration(days: 3)),
      dataFim: base.subtract(const Duration(days: 3)).add(const Duration(hours: 4)),
      valorEstimado: 125,
      raioEntregaKm: 8,
      status: StatusTurno.finalizado,
      pagamentoStatus: PagamentoStatus.pendente,
    ),
    Turno(
      id: 402,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Concluído — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      dataInicio: base.subtract(const Duration(days: 7)),
      dataFim: base.subtract(const Duration(days: 7)).add(const Duration(hours: 4)),
      valorEstimado: 120,
      raioEntregaKm: 8,
      status: StatusTurno.finalizado,
      pagamentoStatus: PagamentoStatus.pago,
    ),
    Turno(
      id: 403,
      lojistId: 2,
      titulo: 'Turno sem candidato',
      regiao: 'Batel, Curitiba',
      dataInicio: base.subtract(const Duration(days: 5)),
      dataFim: base.subtract(const Duration(days: 5)).add(const Duration(hours: 4)),
      valorEstimado: 150,
      raioEntregaKm: 5,
      status: StatusTurno.expirado,
    ),
  ];
}

/// Fake para os goldens do histórico: só turnos encerrados, com data absoluta.
///
/// Com a API quebrada por domínio, a variante troca só o TurnoApi — os outros
/// sete domínios continuam vindo do [FakeApiService].
class FakeTurnoApiHistorico extends FakeTurnoApi {
  @override
  Future<List<Turno>> listarMeusTurnos(int motoboyId) async =>
      fakeTurnosEncerradosFixos();

  @override
  Future<List<Turno>> listarTurnosLojista(int lojistId) async =>
      fakeTurnosEncerradosFixos();
}

class FakeApiHistorico extends FakeApiService {
  @override
  TurnoApi get turnos => _turnosHistorico;
  final TurnoApi _turnosHistorico = FakeTurnoApiHistorico();
}

/// Fake para os goldens de dashboard: a mesma lista de sempre, só que ancorada
/// no [dataAncoraGolden] em vez de em hoje.
///
/// O dashboard desenha os ganhos dos últimos sete dias com o dia da semana em
/// cada barra. Com fixture relativa a hoje, esses rótulos giram todo dia e o
/// golden amanhece vermelho — foi o que aconteceu na virada de 27 para 28/08.
class FakeTurnoApiDatasFixas extends FakeTurnoApi {
  /// Meia-noite do dia da âncora. Os fakes usam a âncora como início do turno
  /// e somam 23h59 para o "dia inteiro"; com a hora do [dataAncoraGolden] o
  /// card exibiria "14:10 - 14:09" em vez de "00:00 - 23:59".
  static final DateTime _dia = DateTime(
      dataAncoraGolden.year, dataAncoraGolden.month, dataAncoraGolden.day);

  @override
  Future<List<Turno>> listarMeusTurnos(int motoboyId) async =>
      fakeMeusTurnos(ancora: _dia);

  @override
  Future<List<Turno>> listarTurnosLojista(int lojistId) async =>
      fakeTurnosLojista(ancora: _dia);
}

class FakeApiDatasFixas extends FakeApiService {
  /// [tipoUsuario] escolhe a carteira e a DRE do papel, como no
  /// [FakeApiService]: o painel da loja mostra o resultado da loja.
  FakeApiDatasFixas({super.tipoUsuario});

  @override
  TurnoApi get turnos => _turnosDatasFixas;
  final TurnoApi _turnosDatasFixas = FakeTurnoApiDatasFixas();
}

// ─────────────────────────────────────────────────────────────────────────────
// Wrapper que monta MaterialApp + Providers + Locale para a tela sob teste
// ─────────────────────────────────────────────────────────────────────────────

/// Renderiza [child] num MaterialApp pré-configurado e captura o golden.
/// Use [argumentos] para passar dados a telas que usam `ModalRoute.of(context)`.
Future<void> pumpGolden(
  WidgetTester tester, {
  required Widget child,
  TipoUsuario tipoUsuario = TipoUsuario.motoboy,
  Object? argumentos,
  Size viewport = const Size(390, 844),
  Duration settle = const Duration(milliseconds: 600),
  int? turnoSelecionado,
  ApiService? apiFake,
  Usuario? usuario,
  LocalizacaoService? localizacao,
}) async {
  // A ordem importa: `physicalSize` precisa ser calculado com o DPR final.
  // Fazendo o inverso (multiplicar pelo DPR padrão da view, 3.0, e só depois
  // zerar para 1.0) a MediaQuery passava a reportar 1170x2532 enquanto a
  // superfície renderizada continuava 390x844 — as duas discordavam, e telas
  // que decidem layout por largura (AdaptiveScaffold) caíam no shell desktop
  // dentro de um frame de celular.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = viewport;
  await tester.binding.setSurfaceSize(viewport);

  // Telas que imprimem data absoluta precisam de um fake de data fixa, senão
  // o golden vira o dia junto com o calendário — ver [FakeApiHistorico].
  final api = apiFake ?? FakeApiService(tipoUsuario: tipoUsuario);
  final logado = usuario ??
      (tipoUsuario == TipoUsuario.motoboy ? fakeMotoboy() : fakeLojista());
  final auth = AuthService(api)..atualizarUsuarioLocal(logado);

  final turnoProv = TurnoProvider(api);
  turnoProv.setDisponiveisExterno(fakeTurnosDisponiveis());

  final selecaoProv = TurnoSelecionadoProvider();
  if (turnoSelecionado != null) selecaoProv.selecionar(turnoSelecionado);

  final widgetTree = MultiProvider(
    providers: [
      Provider<ApiService>.value(value: api),
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<TurnoProvider>.value(value: turnoProv),
      ChangeNotifierProvider<TurnoSelecionadoProvider>.value(
          value: selecaoProv),
      ChangeNotifierProvider<NotificacaoProvider>(
        create: (_) => NotificacaoProvider(api),
      ),
      ChangeNotifierProvider<PendenciasProvider>(
        create: (_) => PendenciasProvider(api),
      ),
      ChangeNotifierProvider<FavoritosProvider>(
        create: (_) => FavoritosProvider(api),
      ),
      // O GPS dos testes. Sem ele as telas usam o do aparelho, que num teste
      // não existe e cai no "erro" — o que também é um caminho válido.
      if (localizacao != null)
        Provider<LocalizacaoService>.value(value: localizacao),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Rota inicial é a tela sob teste (com arguments).
      // Qualquer pushReplacementNamed/pushNamed cai numa página em branco
      // — evita crash em Splash e telas que navegam após verificação.
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(
            settings: RouteSettings(name: '/', arguments: argumentos),
            builder: (_) => child,
          );
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const _BlankPage(),
        );
      },
    ),
  );

  // runAsync libera timers/HTTP reais — deixa GoogleFonts terminar download +
  // sockets bloqueados resolverem antes do snapshot.
  await tester.runAsync(() async {
    await tester.pumpWidget(widgetTree);
    await Future.delayed(const Duration(seconds: 2));
  });
  await tester.pump();
  await tester.pump(settle);
}

/// Página vazia usada como destino fallback de navegações que ocorrem durante
/// o teste (ex: Splash → Login). Não aparece no golden — capturamos a tela
/// original via find.byType().
class _BlankPage extends StatelessWidget {
  const _BlankPage();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SizedBox.shrink());
}

/// Registra as fontes do tema a partir dos arquivos EMBARCADOS (assets/fonts),
/// com os nomes de família que o google_fonts usa.
///
/// Antes isto registrava uma fonte do sistema (Segoe UI no Windows, Arial,
/// DejaVu...) com os nomes da Bricolage e da Jakarta: os goldens não mostravam
/// a cara do app, e mudavam de máquina para máquina. Com as fontes no
/// repositório, o teste desenha o que o usuário vê.
///
/// Por que registrar à mão, se o google_fonts acharia os arquivos nos assets:
/// ele carrega a fonte de forma assíncrona na primeira vez em que o estilo é
/// pedido, e dentro de um testWidgets essa E/S não termina antes do frame que
/// o golden fotografa. Aqui (setUpAll, fora do relógio falso) ela já chega
/// carregada.
///
/// O google_fonts gera fontFamily no formato `FamiliaSemEspaco_variante`:
/// "regular" para o peso 400 e o número para os demais ("700"). Os pesos que o
/// app não embarca (100 a 300, 900) caem no vizinho mais próximo, como o motor
/// de texto faria.
Future<void> _registrarFontesDoTema() async {
  const arquivoDoPeso = {
    '100': 'Regular',
    '200': 'Regular',
    '300': 'Regular',
    'regular': 'Regular',
    '400': 'Regular',
    '500': 'Medium',
    '600': 'SemiBold',
    '700': 'Bold',
    '800': 'ExtraBold',
    '900': 'ExtraBold',
  };

  final cache = <String, ByteData>{};
  ByteData bytesDe(String familia, String peso) => cache.putIfAbsent(
      '$familia-$peso',
      () => ByteData.sublistView(
          File('assets/fonts/$familia-$peso.ttf').readAsBytesSync()));

  int total = 0;
  for (final familia in const ['BricolageGrotesque', 'PlusJakartaSans']) {
    // O nome puro da família é o fontFamilyFallback dos estilos gerados.
    final nomes = <String, String>{familia: 'Regular'};
    arquivoDoPeso.forEach((variante, peso) => nomes['${familia}_$variante'] = peso);

    for (final entrada in nomes.entries) {
      final carregador = FontLoader(entrada.key)
        ..addFont(Future.value(bytesDe(familia, entrada.value)));
      await carregador.load();
      total++;
    }
  }
  // ignore: avoid_print
  print('[golden-fonts] fontes do tema (assets/fonts): $total variações');
}

/// Registra as fontes de ícones do app: a MaterialIcons e o que mais o
/// FontManifest do build declarar.
///
/// O flutter_test não carrega fonte nenhuma, e as de ícone não são exceção:
/// todo ícone saía como um quadrado do tamanho dele. O golden conferia que
/// "há um ícone ali", e não qual — trocar a seta pela lixeira passava sem
/// ninguém ver (SCRUM-49).
///
/// Lê o FontManifest.json em vez de apontar o arquivo: é a mesma lista que o
/// app carrega ao abrir, então uma fonte de ícones nova (um pacote, a
/// CupertinoIcons) entra aqui sozinha. Se a MaterialIcons não estiver nele, a
/// suíte para — melhor do que voltar aos quadrados em silêncio.
Future<void> _registrarFontesDeIcones() async {
  final manifesto =
      json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;

  final familias = <String>[];
  for (final entrada in manifesto.cast<Map<String, dynamic>>()) {
    final familia = entrada['family'] as String;
    final carregador = FontLoader(familia);
    for (final fonte in (entrada['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      carregador.addFont(rootBundle.load(fonte['asset'] as String));
    }
    await carregador.load();
    familias.add(familia);
  }
  if (!familias.contains('MaterialIcons')) {
    throw StateError(
        'A fonte MaterialIcons não está no FontManifest.json (famílias: $familias). '
        'O pubspec.yaml precisa de "uses-material-design: true".');
  }
  // ignore: avoid_print
  print('[golden-fonts] fontes de ícones (FontManifest): ${familias.join(', ')}');
}

// ─────────────────────────────────────────────────────────────────────────────
// HttpOverrides: nenhuma requisição sai da suíte (tiles OSM, fontes, nada)
// ─────────────────────────────────────────────────────────────────────────────

class _SelectiveHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _SelectiveHttpClient(super.createHttpClient(context));
}

class _SelectiveHttpClient implements HttpClient {
  _SelectiveHttpClient(this._real);
  final HttpClient _real;

  /// Nada passa. As fontes do Google passavam — a suíte baixava fonte da
  /// internet no meio dos testes —, e não precisam mais: estão embarcadas em
  /// assets/fonts. Teste que depende de rede passa ou falha conforme o Wi-Fi.
  bool _allow(Uri url) => false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _allow(url)
      ? _real.getUrl(url)
      : Future.value(_MockHttpClientRequest(url));
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _allow(url)
      ? _real.openUrl(method, url)
      : Future.value(_MockHttpClientRequest(url));

  // Delegação para os demais métodos
  @override
  bool get autoUncompress => _real.autoUncompress;
  @override
  set autoUncompress(bool v) => _real.autoUncompress = v;
  @override
  Duration? get connectionTimeout => _real.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _real.connectionTimeout = v;
  @override
  Duration get idleTimeout => _real.idleTimeout;
  @override
  set idleTimeout(Duration v) => _real.idleTimeout = v;
  @override
  int? get maxConnectionsPerHost => _real.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _real.maxConnectionsPerHost = v;
  @override
  String? get userAgent => _real.userAgent;
  @override
  set userAgent(String? v) => _real.userAgent = v;

  @override
  Future<HttpClientRequest> open(
          String method, String host, int port, String path) =>
      openUrl(method, Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      getUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      postUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      Future.value(_MockHttpClientRequest());
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      putUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> putUrl(Uri url) =>
      Future.value(_MockHttpClientRequest());
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      deleteUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) =>
      Future.value(_MockHttpClientRequest());
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      patchUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      Future.value(_MockHttpClientRequest());
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      headUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> headUrl(Uri url) =>
      Future.value(_MockHttpClientRequest());

  @override
  void close({bool force = false}) => _real.close(force: force);
  @override
  set authenticate(
      Future<bool> Function(Uri url, String scheme, String? realm)? f) {
    _real.authenticate = f;
  }

  @override
  set authenticateProxy(
      Future<bool> Function(
              String host, int port, String scheme, String? realm)?
          f) {
    _real.authenticateProxy = f;
  }

  @override
  set badCertificateCallback(
      bool Function(X509Certificate cert, String host, int port)? f) {
    _real.badCertificateCallback = f;
  }

  @override
  set connectionFactory(
      Future<ConnectionTask<Socket>> Function(
              Uri url, String? proxyHost, int? proxyPort)?
          f) {
    _real.connectionFactory = f;
  }

  @override
  set findProxy(String Function(Uri url)? f) {
    _real.findProxy = f;
  }

  @override
  set keyLog(Function(String line)? callback) {
    _real.keyLog = callback;
  }

  @override
  void addCredentials(
          Uri url, String realm, HttpClientCredentials credentials) =>
      _real.addCredentials(url, realm, credentials);
  @override
  void addProxyCredentials(String host, int port, String realm,
          HttpClientCredentials credentials) =>
      _real.addProxyCredentials(host, port, realm, credentials);
}


class _MockHttpClientRequest implements HttpClientRequest {
  _MockHttpClientRequest([Uri? url]) {
    if (url != null) uri = url;
  }

  /// Requisição de imagem recebe um PNG de verdade; o resto, corpo vazio.
  ///
  /// Corpo vazio para tudo era o comportamento anterior, e funcionava enquanto
  /// o único cliente era o google_fonts (que trata a fonte vazia como falha e
  /// cai no fallback). Para um tile do mapa, porém, zero byte vira "Invalid
  /// image data" — uma exceção por tile, que o `flutter_test` conta como falha
  /// do teste. Devolver 1x1 transparente mantém a rede bloqueada e deixa o
  /// decodificador terminar em paz.
  bool get _pedeImagem {
    final path = uri.path.toLowerCase();
    return path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.webp');
  }

  @override
  Future<HttpClientResponse> close() async =>
      _MockHttpClientResponse(imagem: _pedeImagem);

  @override
  HttpHeaders get headers => _MockHeaders();
  @override
  List<Cookie> get cookies => [];
  @override
  Future<HttpClientResponse> get done async =>
      _MockHttpClientResponse(imagem: _pedeImagem);
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;
  @override
  String method = 'GET';
  @override
  Uri uri = Uri.parse('http://mock');
  @override
  int contentLength = 0;
  @override
  Encoding encoding = utf8;
  @override
  bool bufferOutput = true;
  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) async {}
  @override
  Future<dynamic> flush() async {}
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  void write(Object? obj) {}
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? obj = '']) {}
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _MockHttpClientResponse({this.imagem = false});

  /// Devolve um PNG 1x1 em vez de corpo vazio — ver [_MockHttpClientRequest].
  final bool imagem;

  List<int> get _corpo => imagem ? _pngTransparente1x1 : const <int>[];

  // 200 OK: faz google_fonts achar que carregou e cair em fallback Roboto sem
  // lançar exception.
  @override
  int get statusCode => 200;
  @override
  String get reasonPhrase => 'OK';
  @override
  int get contentLength => _corpo.length;
  @override
  HttpHeaders get headers => _MockHeaders();
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  List<Cookie> get cookies => [];
  @override
  List<RedirectInfo> get redirects => [];
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  X509Certificate? get certificate => null;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(Uint8List.fromList(_corpo)).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  Future<Socket> detachSocket() => throw UnimplementedError();

  @override
  Future<HttpClientResponse> redirect(
          [String? method, Uri? url, bool? followLoops]) =>
      throw UnimplementedError();
}

class _MockHeaders implements HttpHeaders {
  @override
  bool chunkedTransferEncoding = false;
  @override
  int contentLength = 0;
  @override
  ContentType? contentType;
  @override
  DateTime? date;
  @override
  DateTime? expires;
  @override
  String? host;
  @override
  DateTime? ifModifiedSince;
  @override
  bool persistentConnection = false;
  @override
  int? port;

  @override
  List<String>? operator [](String name) => null;
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void clear() {}
  @override
  void forEach(void Function(String name, List<String> values) action) {}
  @override
  void noFolding(String name) {}
  @override
  void remove(String name, Object value) {}
  @override
  void removeAll(String name) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  String? value(String name) => null;
}

/// PNG 1x1 totalmente transparente.
///
/// É o corpo que o cliente HTTP falso devolve para qualquer requisição de
/// imagem — tile de mapa, principalmente. Precisa ser um PNG válido de
/// verdade: bytes arbitrários (ou nenhum) fazem o decodificador lançar
/// "Invalid image data", e o `flutter_test` trata cada uma dessas exceções
/// como falha do teste que estava rodando.
const List<int> _pngTransparente1x1 = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // assinatura PNG
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR (13 bytes)
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89,
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT (10 bytes)
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05,
  0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND
  0xAE, 0x42, 0x60, 0x82,
];

/// Finge o plugin `printing` e guarda o que ele recebeu: o PDF e o nome do
/// arquivo. Sem isto, "Baixar PDF" num teste cai num canal de plataforma que
/// não existe.
class PdfEntregue {
  Uint8List? bytes;
  String? nome;
}

PdfEntregue fingirImpressora(WidgetTester tester) {
  final entregue = PdfEntregue();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('net.nfet.printing'),
    (call) async {
      if (call.method == 'sharePdf') {
        final args = (call.arguments as Map).cast<String, dynamic>();
        entregue.bytes = args['doc'] as Uint8List;
        entregue.nome = args['name'] as String?;
        return 1;
      }
      return null;
    },
  );
  return entregue;
}

/// Finge o download e guarda os arquivos que a tela entregou — o CSV da
/// planilha e o .ics do calendário. Sem isto, `baixarArquivo` cai na folha de
/// compartilhar do sistema, que num teste não existe.
List<ArquivoBaixado> fingirDownload() {
  final baixados = <ArquivoBaixado>[];
  final anterior = trocarEntregaDeArquivo((a) async => baixados.add(a));
  addTearDown(() => trocarEntregaDeArquivo(anterior));
  return baixados;
}
