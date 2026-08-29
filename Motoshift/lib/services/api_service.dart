import 'api/agenda_api.dart';
import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/avaliacao_api.dart';
import 'api/carteira_api.dart';
import 'api/dashboard_api.dart';
import 'api/ia_api.dart';
import 'api/notificacao_api.dart';
import 'api/turno_api.dart';

export 'api/api_client.dart' show ApiException;

// ============================================================
//  ApiService — a porta de entrada para o backend Spring Boot
// ============================================================

/// Reúne as APIs por domínio sobre um único [ApiClient].
///
/// Esta classe tinha 459 linhas e 45 endpoints: autenticação, usuários, turnos,
/// carteira, dashboard, IA, agenda, avaliações e notificações no mesmo arquivo,
/// mais `rawGet`/`rawPost`/`rawPut` públicos — um encapsulamento com uma porta
/// ao lado escrito "entre por aqui". Sobrou o que ela sempre deveria ter sido:
/// a montagem. Cada domínio virou um arquivo em `services/api/`, e o transporte
/// (cabeçalho, timeout, erro, token) mora só no [ApiClient].
///
/// As telas continuam lendo um `ApiService` do provider, mas chamam
/// `api.turnos.criarTurno(...)`, `api.carteira.buscarCarteira(...)` e assim por
/// diante. Nos testes, o fake sobrescreve o getter do domínio que aquele teste
/// exercita, em vez de reimplementar a API inteira.
class ApiService {
  final ApiClient client;

  late final AuthApi auth = AuthApi(client);
  late final TurnoApi turnos = TurnoApi(client);
  late final CarteiraApi carteira = CarteiraApi(client);
  late final AvaliacaoApi avaliacoes = AvaliacaoApi(client);
  late final NotificacaoApi notificacoes = NotificacaoApi(client);
  late final AgendaApi agenda = AgendaApi(client);
  late final DashboardApi dashboard = DashboardApi(client);
  late final IaApi ia = IaApi(client);

  ApiService({ApiClient? client}) : client = client ?? ApiClient();

  /// Sessão. O token é assunto do transporte, então quem o guarda é o
  /// [ApiClient]; estes três só dão ao AuthService um nome estável para chamar.
  void setAuthToken(String token) => client.setAuthToken(token);

  void clearAuthToken() => client.clearAuthToken();

  set onSessaoExpirada(void Function()? callback) =>
      client.onSessaoExpirada = callback;
}
