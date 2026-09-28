import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/presenca.dart';
import '../models/turno.dart';
import '../models/usuario.dart';
import '../presentation/providers/turno_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/localizacao_service.dart';
import '../theme/app_theme.dart';
import 'app_buttons.dart';

/// "Cheguei" e "Encerrar turno": a presença do entregador no turno (V16).
///
/// Mora no detalhe do turno do entregador, acima das ações. Só aparece para
/// quem está no turno, enquanto ele não acabou. A regra — janela de 30 min
/// antes do início até o fim, até 500 m do ponto — é do backend; aqui a tela
/// pega a posição pelo [LocalizacaoService] (com as mensagens de falha que
/// ele já tem) e mostra o que o backend responder, inclusive "Você está a
/// 1,2 km do local".
///
/// Encerrar não é finalizar: o check-out registra a saída; o pagamento sai
/// quando o turno for finalizado, pelo "Finalizar turno" logo abaixo.
class CheckinDoTurno extends StatefulWidget {
  const CheckinDoTurno({required this.turno, this.margem, super.key});

  final Turno turno;
  final EdgeInsets? margem;

  @override
  State<CheckinDoTurno> createState() => _CheckinDoTurnoState();
}

class _CheckinDoTurnoState extends State<CheckinDoTurno> {
  /// Nula enquanto carrega — e quando o entregador não está entre os
  /// inscritos, caso em que o bloco não aparece.
  Presenca? _presenca;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  @override
  void didUpdateWidget(CheckinDoTurno antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.turno.id != widget.turno.id) {
      _presenca = null;
      _carregar();
    }
  }

  bool get _turnoVivo =>
      widget.turno.status == StatusTurno.aberto ||
      widget.turno.status == StatusTurno.aceito ||
      widget.turno.status == StatusTurno.emAndamento;

  Future<void> _carregar() async {
    final eu = context.read<AuthService>().usuario;
    final id = widget.turno.id;
    if (id == null || eu?.id == null || eu!.tipo != TipoUsuario.motoboy) return;
    if (!_turnoVivo) return;
    try {
      final inscritos = await context.read<ApiService>().turnos.listarInscritos(id);
      final meu = inscritos
          .where((m) => (m['motoboyId'] as num?)?.toInt() == eu.id)
          .firstOrNull;
      if (!mounted) return;
      setState(() => _presenca = meu == null ? null : Presenca.doInscrito(meu));
    } catch (_) {
      // Sem a lista não dá para saber se já chegou: melhor não oferecer o
      // botão do que oferecer o errado.
    }
  }

  Future<void> _cheguei() async {
    final id = widget.turno.id;
    if (id == null) return;
    setState(() => _ocupado = true);

    final pos = await LocalizacaoService.of(context).posicaoAtual();
    if (!mounted) return;
    try {
      // Sem posição, tenta assim mesmo: com a trava de proximidade desligada
      // (apresentação feita de casa) o backend aceita.
      await context.read<ApiService>().turnos.checkin(id,
          latitude: pos.latitude, longitude: pos.longitude);
      if (!mounted) return;
      _aviso('Chegada registrada. Bom turno!', AppColors.good);
      await _depoisDeMudar();
    } on ApiException catch (e) {
      // O backend exige a posição e ela não veio: o motivo do GPS diz mais do
      // que "envie a sua localização".
      final msg = !pos.temPosicao && e.statusCode == 400
          ? (pos.falha ?? FalhaLocalizacao.erro).mensagem
          : e.message;
      _aviso(msg, AppColors.error);
    } catch (_) {
      _aviso('Não foi possível registrar a chegada agora.', AppColors.error);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _encerrar() async {
    final id = widget.turno.id;
    if (id == null) return;
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Encerrar turno',
            style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        content: Text(
          'Registra a sua saída agora. O pagamento sai quando o turno for '
          'finalizado — por você ou pela loja.',
          style: tsJakarta(13, FontWeight.w400, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Voltar',
                style: tsJakarta(13, FontWeight.w600, color: AppColors.muted)),
          ),
          TextButton(
            key: const Key('confirmar-encerrar'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Encerrar',
                style: tsJakarta(13, FontWeight.w700, color: AppColors.teal)),
          ),
        ],
      ),
    );
    if (confirma != true || !mounted) return;

    setState(() => _ocupado = true);
    try {
      await context.read<ApiService>().turnos.checkout(id);
      if (!mounted) return;
      _aviso('Saída registrada.', AppColors.good);
      await _depoisDeMudar();
    } on ApiException catch (e) {
      _aviso(e.message, AppColors.error);
    } catch (_) {
      _aviso('Não foi possível registrar a saída agora.', AppColors.error);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// A presença e a lista de turnos mudam juntas: o primeiro check-in leva o
  /// turno a "Em andamento".
  Future<void> _depoisDeMudar() async {
    await _carregar();
    if (!mounted) return;
    final eu = context.read<AuthService>().usuario?.id;
    if (eu != null) context.read<TurnoProvider>().carregarMeusTurnos(eu);
  }

  void _aviso(String texto, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: cor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presenca = _presenca;
    if (presenca == null || !_turnoVivo) return const SizedBox.shrink();

    final String texto;
    final Widget? botao;
    if (!presenca.chegou) {
      texto = 'Toque em "Cheguei" quando chegar ao ponto do turno. Vale de 30 '
          'minutos antes do início até o fim, a até 500 m do local.';
      botao = PrimaryButton(
        key: const Key('acao-cheguei'),
        label: 'Cheguei',
        loading: _ocupado,
        onPressed: _ocupado ? null : _cheguei,
        icon: const Icon(Icons.where_to_vote_outlined,
            color: Colors.white, size: 18),
      );
    } else if (!presenca.saiu) {
      texto = '${presenca.rotuloChegada}.';
      botao = GhostButton(
        key: const Key('acao-encerrar'),
        label: 'Encerrar turno',
        onPressed: _ocupado ? null : _encerrar,
      );
    } else {
      texto = '${presenca.resumo}.';
      botao = null;
    }

    return Padding(
      padding: widget.margem ?? EdgeInsets.zero,
      child: Container(
        key: const Key('presenca-do-turno'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: presenca.chegou ? AppColors.teal : AppColors.line,
              width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                    presenca.chegou
                        ? Icons.where_to_vote_rounded
                        : Icons.pin_drop_outlined,
                    size: 15,
                    color: AppColors.teal),
                const SizedBox(width: 6),
                Text('PRESENÇA',
                    style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)
                        .copyWith(letterSpacing: 0.9)),
              ],
            ),
            const SizedBox(height: 8),
            Text(texto,
                key: const Key('presenca-texto'),
                style: tsJakarta(12, FontWeight.w500,
                    color: AppColors.text, height: 1.4)),
            if (botao != null) ...[
              const SizedBox(height: 10),
              botao,
            ],
          ],
        ),
      ),
    );
  }
}
