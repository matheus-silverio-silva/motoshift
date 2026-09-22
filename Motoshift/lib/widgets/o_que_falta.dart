import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/turno.dart';
import '../models/usuario.dart';
import '../presentation/providers/pendencias_provider.dart';
import '../routes/abrir_avaliacao.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// O que ainda falta neste turno, depois que ele acabou.
///
/// <h3>Por que existe</h3>
/// O turno terminava e a interface parava de falar sobre ele. A avaliação e a
/// nota fiscal continuavam pendentes, mas só apareciam em telas distantes — a
/// central de Avaliações e a lista de Notas —, e nada no próprio turno dizia
/// que havia algo a fazer. Quem abria o turno concluído via um rodapé escrito
/// "Turno finalizado" e nenhuma saída.
///
/// <h3>O que NÃO entra aqui</h3>
/// Pagamento. O dinheiro é reservado quando o turno é publicado e transferido
/// na finalização, dentro da mesma transação — não há nada para a pessoa
/// confirmar, e um botão sugerindo o contrário reintroduziria a dupla
/// confirmação manual que foi removida de propósito. O extrato conta essa
/// história; este bloco só lista o que depende de uma ação.
class OQueFalta extends StatefulWidget {
  const OQueFalta({
    required this.turno,
    this.margem = const EdgeInsets.only(bottom: 12),
    super.key,
  });

  final Turno turno;

  /// O espaço em volta do bloco mora aqui, e não em quem chama — a mesma
  /// regra do PainelPendencias. Como o bloco some sozinho quando não há
  /// pendência, um espaçador do lado de fora ficaria sobrando na tela de todo
  /// turno em aberto.
  final EdgeInsetsGeometry margem;

  @override
  State<OQueFalta> createState() => _OQueFaltaState();
}

class _OQueFaltaState extends State<OQueFalta> {
  @override
  void initState() {
    super.initState();
    // O detalhe do turno no celular não tem menu, então pode ser a primeira
    // tela da sessão a precisar das pendências.
    WidgetsBinding.instance.addPostFrameCallback((_) => _garantir());
  }

  void _garantir() {
    if (!mounted) return;
    context
        .read<PendenciasProvider>()
        .garantirCarregado(context.read<AuthService>().usuario);
  }

  @override
  Widget build(BuildContext context) {
    // Só turno finalizado tem "o que falta": no aberto ou em andamento a
    // pendência ainda não nasceu, e no cancelado nunca vai nascer.
    if (widget.turno.status != StatusTurno.finalizado) {
      return const SizedBox.shrink();
    }

    final pendencias = context.watch<PendenciasProvider>();
    final avaliacoes = pendencias.avaliacoesDoTurno(widget.turno.id);
    final notas = pendencias.notasDoTurno(widget.turno.id);
    if (avaliacoes.isEmpty && notas.isEmpty) return const SizedBox.shrink();

    final ehLojista =
        context.read<AuthService>().usuario?.tipo == TipoUsuario.lojista;

    return Container(
      margin: widget.margem,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('O QUE FALTA',
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)
                  .copyWith(letterSpacing: 0.9)),
          const SizedBox(height: 10),
          if (avaliacoes.isNotEmpty)
            _Item(
              key: const Key('o-que-falta-avaliar'),
              icone: Icons.star_outline_rounded,
              cor: AppColors.amber,
              titulo: _tituloAvaliacao(avaliacoes.length, ehLojista),
              subtitulo: avaliacoes.map((p) => p.nome).join(', '),
              onTap: () => _avaliar(),
            ),
          if (avaliacoes.isNotEmpty && notas.isNotEmpty)
            const SizedBox(height: 8),
          if (notas.isNotEmpty)
            _Item(
              key: const Key('o-que-falta-nota'),
              icone: Icons.receipt_long_outlined,
              cor: AppColors.teal,
              titulo: notas.length == 1
                  ? 'Emitir a nota fiscal'
                  : 'Emitir ${notas.length} notas fiscais',
              subtitulo: 'A NFS-e deste turno ainda não foi emitida.',
              onTap: _abrirNotas,
            ),
        ],
      ),
    );
  }

  String _tituloAvaliacao(int quantas, bool ehLojista) {
    if (!ehLojista) return 'Avaliar a loja';
    return quantas == 1 ? 'Avaliar o entregador' : 'Avaliar $quantas entregadores';
  }

  Future<void> _avaliar() async {
    await abrirAvaliacao(context, widget.turno);
    _recarregar();
  }

  Future<void> _abrirNotas() async {
    await Navigator.pushNamed(context, AppRoutes.notasFiscais);
    _recarregar();
  }

  /// Recarrega ao voltar: a pendência costuma ter sido resolvida lá dentro, e
  /// o bloco precisa sumir sem a pessoa ter de recarregar a tela.
  void _recarregar() {
    if (!mounted) return;
    context
        .read<PendenciasProvider>()
        .carregar(context.read<AuthService>().usuario);
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
    super.key,
  });

  final IconData icone;
  final Color cor;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, size: 16, color: cor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tsJakarta(12.5, FontWeight.w700,
                            color: AppColors.ink)),
                    const SizedBox(height: 1),
                    Text(subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tsJakarta(10.5, FontWeight.w400,
                            color: AppColors.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
