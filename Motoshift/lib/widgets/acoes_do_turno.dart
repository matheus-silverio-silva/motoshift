import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/repeticao_de_turno.dart';
import '../models/turno.dart';
import '../models/usuario.dart';
import '../presentation/providers/pendencias_provider.dart';
import '../presentation/providers/turno_provider.dart';
import '../routes/abrir_avaliacao.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'app_buttons.dart';

/// As ações possíveis num turno, para os dois lados.
///
/// <h3>Por que uma só, e por que aqui</h3>
/// Finalizar e cancelar eram privilégio de quem estivesse na tela certa. O
/// entregador só finalizava pelo card de "turno em andamento" da lista; no
/// detalhe do turno, o rodapé dizia "Turno aceito" e mais nada. O lojista não
/// tinha "Finalizar" em lugar nenhum — apesar de o backend aceitar a
/// finalização **dos dois participantes** desde que o dinheiro passou a ser
/// reservado na publicação. Quem abrisse o turno pelo caminho errado ficava
/// sem a ação.
///
/// As regras aqui são as de `TurnoService`, não uma aproximação:
///
/// * finalizar vale para o turno que já começou e em que alguém fez check-in
///   ([Turno.podeSerFinalizado]) — só quem fez check-in é pago, e qualquer
///   um dos dois participantes pode finalizar;
/// * sair do turno é uma ação para cada lado. O **lojista** vê "Cancelar
///   turno": o turno inteiro cai, a reserva volta e nenhum entregador é
///   penalizado. O **entregador** vê "Desistir da vaga": só a vaga dele é
///   liberada, o turno segue, e a menos de 1 hora do início a desistência
///   custa 0,5 do score dele. Era um botão só, e a penalidade caía no
///   entregador mesmo quando quem cancelava era a loja;
/// * nenhuma das duas vale com check-in feito: o turno começou, e a saída é
///   finalizar;
/// * o turno finalizado não tem mais nada a fazer além de avaliar — e é o
///   [OQueFalta] logo acima que lista a nota fiscal;
/// * o lojista publica de novo o turno que acabou (finalizado, cancelado ou
///   expirado): o formulário abre preenchido, e publicar continua passando
///   pela confirmação do custo — ver [RepeticaoDeTurno].
class AcoesDoTurno extends StatefulWidget {
  const AcoesDoTurno({
    required this.turno,
    this.onAceitar,
    this.aceitando = false,
    this.onMudou,
    this.emLinha = false,
    super.key,
  });

  final Turno turno;

  /// Só o entregador aceita, e a ação mora na tela que já cuidava dela.
  final VoidCallback? onAceitar;
  final bool aceitando;

  /// Chamado depois de finalizar, cancelar ou desistir — quem hospeda decide se dá
  /// `pop` (mobile) ou recarrega a lista (desktop).
  final VoidCallback? onMudou;

  /// `true` põe os botões lado a lado, para o painel largo do desktop.
  final bool emLinha;

  @override
  State<AcoesDoTurno> createState() => _AcoesDoTurnoState();
}

class _AcoesDoTurnoState extends State<AcoesDoTurno> {
  bool _ocupado = false;

  Turno get _turno => widget.turno;

  bool get _ehLojista =>
      context.read<AuthService>().usuario?.tipo == TipoUsuario.lojista;

  /// O entregador já está neste turno? Num turno multi-vaga o status continua
  /// `aberto` enquanto sobrar vaga, então o status sozinho não responde — e
  /// sem isto o detalhe oferecia "Aceitar turno" a quem já tinha aceitado,
  /// para o backend recusar com "Você já aceitou este turno".
  bool get _jaSouDoTurno {
    final meus = context.watch<TurnoProvider>().meusTurnos;
    return meus.any((t) => t.id != null && t.id == _turno.id);
  }

  @override
  Widget build(BuildContext context) {
    final acoes = _acoes();
    if (_ehLojista && RepeticaoDeTurno.podeRepetir(_turno)) {
      // Sem outra ação, o estado continua dito ao lado do botão.
      if (acoes.isEmpty) acoes.add(_Inerte(turno: _turno));
      acoes.add(GhostButton(
        key: const Key('acao-publicar-de-novo'),
        label: 'Publicar de novo',
        icon: const Icon(Icons.replay_rounded,
            size: 17, color: AppColors.tealDeep),
        onPressed: _publicarDeNovo,
      ));
    }
    if (acoes.isEmpty) return _Inerte(turno: _turno);
    if (acoes.length == 1) return acoes.first;
    return widget.emLinha
        ? Row(
            children: [
              for (var i = 0; i < acoes.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: acoes[i]),
              ],
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < acoes.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                acoes[i],
              ],
            ],
          );
  }

  List<Widget> _acoes() {
    switch (_turno.status) {
      case StatusTurno.cancelado:
      case StatusTurno.expirado:
        return [];

      case StatusTurno.finalizado:
        final pendentes =
            context.watch<PendenciasProvider>().avaliacoesDoTurno(_turno.id);
        if (pendentes.isEmpty) return [];
        return [
          PrimaryButton(
            key: const Key('acao-avaliar'),
            label: _ehLojista
                ? (pendentes.length == 1
                    ? 'Avaliar o entregador'
                    : 'Avaliar entregadores')
                : 'Avaliar a loja',
            onPressed: _avaliar,
          ),
        ];

      case StatusTurno.aberto:
      case StatusTurno.aceito:
      case StatusTurno.emAndamento:
        if (!_ehLojista && !_jaSouDoTurno) {
          // Vaga livre: a única ação do entregador é entrar.
          return [
            if (widget.onAceitar != null && _turno.status == StatusTurno.aberto)
              PrimaryButton(
                key: const Key('acao-aceitar'),
                label: 'Aceitar turno',
                loading: widget.aceitando,
                onPressed: widget.onAceitar!,
              ),
          ];
        }
        return [
          // Finalizar só existe quando o backend aceitaria: o turno já começou
          // e alguém fez check-in. Fora disso a chamada volta 409 — e era por
          // aqui que o entregador finalizava o turno de amanhã e recebia.
          if (_turno.podeSerFinalizado())
            PrimaryButton(
              key: const Key('acao-finalizar'),
              label: 'Finalizar turno',
              loading: _ocupado,
              onPressed: _ocupado ? null : _finalizar,
            ),
          // Turno em andamento não se cancela nem se larga: alguém fez
          // check-in e está trabalhando — o backend recusa, e a saída é
          // finalizar. Fora disso, cada lado tem a sua ação: a loja cancela o
          // turno; o entregador desiste da vaga dele.
          if (_turno.status != StatusTurno.emAndamento)
            _ehLojista
                ? GhostButton(
                    key: const Key('acao-cancelar'),
                    label: 'Cancelar turno',
                    danger: true,
                    onPressed: _ocupado ? null : _cancelar,
                  )
                : GhostButton(
                    key: const Key('acao-desistir'),
                    label: 'Desistir da vaga',
                    danger: true,
                    onPressed: _ocupado ? null : _desistir,
                  ),
        ];
    }
  }

  /// Abre o formulário de publicar preenchido com este turno. Se o novo for
  /// publicado, quem hospeda recarrega (desktop) ou volta à lista (mobile).
  Future<void> _publicarDeNovo() async {
    final publicou = await Navigator.of(context)
        .pushNamed(AppRoutes.publicarTurno, arguments: _turno);
    if (publicou == true && mounted) widget.onMudou?.call();
  }

  Future<void> _avaliar() async {
    await abrirAvaliacao(context, _turno);
    if (!mounted) return;
    context
        .read<PendenciasProvider>()
        .carregar(context.read<AuthService>().usuario);
    widget.onMudou?.call();
  }

  /// Finaliza e leva direto à avaliação.
  ///
  /// Os dois lados, e não só o entregador: o backend notifica os dois
  /// participantes com "avaliacao_pendente" na mesma transação, e não havia
  /// motivo para o lojista ter de ir procurar a tela depois.
  Future<void> _finalizar() async {
    final id = _turno.id;
    if (id == null) return;
    final provider = context.read<TurnoProvider>();

    setState(() => _ocupado = true);
    final ok = await provider.finalizarTurno(id);
    if (!mounted) return;
    setState(() => _ocupado = false);

    if (!ok) {
      _aviso(provider.erro ?? 'Não foi possível finalizar o turno.',
          AppColors.error);
      return;
    }

    _aviso('Turno finalizado. O pagamento foi liquidado.', AppColors.good);
    await abrirAvaliacao(context, _turno);
    if (!mounted) return;
    context
        .read<PendenciasProvider>()
        .carregar(context.read<AuthService>().usuario);
    widget.onMudou?.call();
  }

  Future<void> _cancelar() async {
    final id = _turno.id;
    if (id == null) return;

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar turno',
            style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        content: Text(
          'O turno é cancelado para todos os entregadores inscritos e o valor '
          'reservado volta inteiro para o seu saldo. Nenhum entregador é '
          'penalizado.',
          style: tsJakarta(13, FontWeight.w400, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Voltar',
                style: tsJakarta(13, FontWeight.w600, color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancelar turno',
                style: tsJakarta(13, FontWeight.w700, color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirma != true || !mounted) return;

    final provider = context.read<TurnoProvider>();
    setState(() => _ocupado = true);
    final ok = await provider.cancelarTurno(id);
    if (!mounted) return;
    setState(() => _ocupado = false);

    _aviso(
      ok ? 'Turno cancelado.' : (provider.erro ?? 'Erro ao cancelar turno.'),
      AppColors.error,
    );
    if (ok) widget.onMudou?.call();
  }

  /// O entregador sai da vaga dele. O diálogo diz, antes do toque, se a
  /// desistência vai custar score — a regra de 1 hora é a do backend
  /// (`Reputacao.FOLGA_SEM_PENALIDADE`), e quem decide de fato é ele.
  Future<void> _desistir() async {
    final id = _turno.id;
    if (id == null) return;

    final emCimaDaHora = clock
        .now()
        .isAfter(_turno.dataInicio.subtract(const Duration(hours: 1)));

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Desistir da vaga',
            style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        content: Text(
          emCimaDaHora
              ? 'Falta menos de 1 hora para o início: desistir agora desconta '
                  '0,5 do seu score. A vaga volta a ficar aberta e a loja é '
                  'avisada.'
              : 'Com mais de 1 hora de antecedência, desistir não muda o seu '
                  'score. A vaga volta a ficar aberta para outro entregador e '
                  'a loja é avisada.',
          key: Key(emCimaDaHora
              ? 'desistir-com-penalidade'
              : 'desistir-sem-penalidade'),
          style: tsJakarta(13, FontWeight.w400, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Voltar',
                style: tsJakarta(13, FontWeight.w600, color: AppColors.muted)),
          ),
          TextButton(
            key: const Key('confirmar-desistir'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Desistir da vaga',
                style: tsJakarta(13, FontWeight.w700, color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirma != true || !mounted) return;

    final provider = context.read<TurnoProvider>();
    setState(() => _ocupado = true);
    final ok = await provider.desistirDaVaga(id);
    if (!mounted) return;
    setState(() => _ocupado = false);

    _aviso(
      ok
          ? 'Você desistiu da vaga.'
          : (provider.erro ?? 'Erro ao desistir da vaga.'),
      AppColors.error,
    );
    if (ok) widget.onMudou?.call();
  }

  void _aviso(String texto, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: cor),
    );
  }
}

/// Fim de linha: nada a fazer, mas o estado continua dito.
class _Inerte extends StatelessWidget {
  const _Inerte({required this.turno});
  final Turno turno;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Center(
        child: Text(
          'Turno ${turno.status.label.toLowerCase()}',
          style: tsJakarta(13, FontWeight.w600, color: AppColors.muted),
        ),
      ),
    );
  }
}
