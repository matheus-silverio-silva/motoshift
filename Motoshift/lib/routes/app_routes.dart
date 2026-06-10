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
  static const String avaliacao         = '/avaliacao';           // tela 7
  static const String perfil            = '/perfil';              // tela 9

  // ── Legadas (mantidas para compatibilidade até remoção) ──────────────────
  static const String meusTurnos        = '/meus-turnos';
  static const String agendarTurno      = '/agendar-turno';
  static const String historico         = '/historico';
  static const String solicitarServico  = '/solicitar-servico';

  // ── Stubs (sub-páginas do perfil / fluxos secundários) ───────────────────
  static const String sacarPix          = '/sacar-pix';
  static const String dadosPessoais     = '/dados-pessoais';
  static const String cnhVeiculo        = '/cnh-veiculo';
  static const String minhasAvaliacoes  = '/minhas-avaliacoes';
  static const String historicoTurnos   = '/historico-turnos';
  static const String esqueceuSenha     = '/esqueceu-senha';
}
