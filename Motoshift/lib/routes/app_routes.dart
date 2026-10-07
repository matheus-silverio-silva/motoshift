/// Constantes de rotas nomeadas — única fonte da verdade para navegação.
class AppRoutes {
  AppRoutes._();

  // ── Core ────────────────────────────────────────────────────────────────
  static const String splash           = '/splash';
  static const String login            = '/login';
  static const String cadastro         = '/cadastro';

  // ── Dashboards ──────────────────────────────────────────────────────────
  static const String dashboardMotoboy = '/dashboard-motoboy';
  static const String dashboardLojista = '/dashboard-lojista';

  // ── Fluxo Lojista ────────────────────────────────────────────────────────
  static const String publicarTurno    = '/publicar-turno';
  static const String turnoLojista     = '/turno-lojista';    // tela 11
  static const String turnosLojista    = '/turnos-lojista';   // lista publicados

  // ── Fluxo Motoboy ────────────────────────────────────────────────────────
  static const String turnosDisponiveis = '/turnos-disponiveis'; // tela 4
  static const String detalheTurno      = '/detalhe-turno';      // tela 10
  static const String carteira          = '/carteira';            // tela 6

  // ── Compartilhadas ───────────────────────────────────────────────────────
  static const String agenda            = '/agenda';              // tela 8
  static const String notasFiscais      = '/notas-fiscais';       // NFS-e
  static const String avaliacao         = '/avaliacao';           // tela 7
  static const String perfil            = '/perfil';              // tela 9
  static const String notificacoes      = '/notificacoes';        // tela 17
  static const String saldoLojista      = '/saldo-lojista';       // tela 21
  static const String avaliarEntregadores =
      '/avaliar-entregadores';                                     // tela 19

  // ── Financeiro ───────────────────────────────────────────────────────────
  // Servem aos dois perfis com a mesma rota, mas cada tela mostra só o que é
  // do papel de quem abriu: o entregador vê recebido, sacado e a receber; o
  // lojista vê recarregado, pago, devolvido e comprometido.
  static const String extrato           = '/extrato';
  static const String lancamento        = '/extrato/lancamento';
  static const String recarga           = '/recarga';
  /// Documento fiscal SIMULADO de um lançamento — NFS-e ou comprovante.
  static const String documentoFiscal   = '/documento';
  static const String relatorioFinanceiro = '/relatorio-financeiro';
  static const String resultado         = '/resultado';           // DRE (RF13)

  // ── Sub-páginas (alcançadas de dentro de outra tela) ─────────────────────
  //
  // /meus-turnos e /agendar-turno saíram: eram apelidos de /turnos-disponiveis
  // e /publicar-turno, registrados para as MESMAS telas. Ninguém navegava para
  // elas — só o teste as listava —, e duas rotas para a mesma tela fazem o
  // destaque do menu depender de por qual delas o usuário chegou.
  //
  // /sacar-pix saiu junto com a SacarPixScreen: era um stub "em breve" enquanto
  // a Carteira já tinha o saque funcionando.
  static const String perfilPublico     = '/perfil-publico';
  static const String dadosPessoais     = '/dados-pessoais';
  static const String cnhVeiculo        = '/cnh-veiculo';
  static const String minhasAvaliacoes  = '/minhas-avaliacoes';
  static const String historicoTurnos   = '/historico-turnos';
  static const String esqueceuSenha     = '/esqueceu-senha';
  static const String alterarSenha      = '/alterar-senha';
}
