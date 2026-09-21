import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/turno.dart';
import '../models/usuario.dart';
import '../presentation/providers/pendencias_provider.dart';
import '../presentation/providers/turno_provider.dart';
import '../routes/abrir_avaliacao.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'app_buttons.dart';

/// As ações possíveis num turno — as mesmas para os dois lados.
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
/// * finalizar e cancelar valem para qualquer status que não seja
///   `FINALIZADO` nem `CANCELADO`, e exigem um entregador no turno;
/// * qualquer participante pode fazer as duas coisas;
/// * o turno finalizado não tem mais nada a fazer além de avaliar — e é o
///   [OQueFalta] logo acima que lista a nota fiscal.
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

  /// Chamado depois de finalizar ou cancelar — quem hospeda decide se dá
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
        return const [];

      case StatusTurno.finalizado:
        final pendentes =
            context.watch<PendenciasProvider>().avaliacoesDoTurno(_turno.id);
        if (pendentes.isEmpty) return const [];
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
          // Finalizar só existe com entregador no turno — é o que o backend
          // exige, e sem ele a chamada voltaria 400.
          if (_turno.motoboyId != null)
            PrimaryButton(
              key: const Key('acao-finalizar'),
              label: 'Finalizar turno',
              loading: _ocupado,
              onPressed: _ocupado ? null : _finalizar,
            ),
          GhostButton(
            key: const Key('acao-cancelar'),
            label: 'Cancelar turno',
            danger: true,
            onPressed: _ocupado ? null : _cancelar,
          ),
        ];
    }
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
          'Cancelar a menos de uma hora do início desconta 0,5 do score do '
          'entregador. O valor reservado volta inteiro para o lojista.',
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
