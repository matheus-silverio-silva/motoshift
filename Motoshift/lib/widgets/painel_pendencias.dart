import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/turno.dart';
import '../models/usuario.dart';
import '../routes/app_routes.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// O que está esperando uma ação do usuário, em uma linha por assunto.
///
/// Existe por causa de duas coisas que o painel não mostrava: a avaliação
/// pendente, que só aparecia se a pessoa fosse até o histórico procurar, e a
/// nota fiscal, que é nova. Em vez de mais um card fixo ocupando espaço, o
/// painel só é montado quando há pendência — sem nada a fazer, ele não existe,
/// e o início continua limpo.
///
/// Carrega os próprios dados e engole falha de rede de propósito: é um resumo
/// auxiliar, e derrubar o início por causa dele seria desproporcional.
class PainelPendencias extends StatefulWidget {
  const PainelPendencias({super.key});

  @override
  State<PainelPendencias> createState() => _PainelPendenciasState();
}

class _PainelPendenciasState extends State<PainelPendencias> {
  int _avaliacoes = 0;
  int _notas = 0;
  bool _pronto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final usuario = auth.usuario;
    if (usuario?.id == null) return;

    final avaliacoes = await _contarAvaliacoes(api, usuario!);
    final notas = await _contarNotas(api);

    if (!mounted) return;
    setState(() {
      _avaliacoes = avaliacoes;
      _notas = notas;
      _pronto = true;
    });
  }

  /// Turnos finalizados que este usuário ainda não avaliou — a mesma regra da
  /// central de avaliações.
  Future<int> _contarAvaliacoes(ApiService api, Usuario usuario) async {
    try {
      final id = usuario.id!;
      final turnos = usuario.tipo == TipoUsuario.lojista
          ? await api.turnos.listarTurnosLojista(id)
          : await api.turnos.listarMeusTurnos(id);
      final avaliados = (await api.avaliacoes.buscarTurnosAvaliados(id)).toSet();
      return turnos
          .where((t) =>
              t.status == StatusTurno.finalizado &&
              t.id != null &&
              !avaliados.contains(t.id))
          .length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _contarNotas(ApiService api) async {
    try {
      return (await api.notasFiscais.pendentes()).length;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_pronto || (_avaliacoes == 0 && _notas == 0)) {
      return const SizedBox.shrink();
    }

    return Container(
      // A margem mora aqui, e não em quem chama: como o painel some sozinho
      // quando não há pendência, um espaçador do lado de fora ficaria pendurado
      // no meio da tela nos dias em que ele não aparece.
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PENDÊNCIAS',
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)
                  .copyWith(letterSpacing: 0.9)),
          const SizedBox(height: 10),
          if (_avaliacoes > 0)
            _Pendencia(
              icone: Icons.star_outline_rounded,
              cor: AppColors.amber,
              titulo: _avaliacoes == 1
                  ? '1 turno para avaliar'
                  : '$_avaliacoes turnos para avaliar',
              subtitulo: 'A nota entra na reputação dos dois lados.',
              onTap: () => _abrir(AppRoutes.minhasAvaliacoes),
            ),
          if (_avaliacoes > 0 && _notas > 0) const SizedBox(height: 8),
          if (_notas > 0)
            _Pendencia(
              icone: Icons.receipt_long_outlined,
              cor: AppColors.teal,
              titulo: _notas == 1
                  ? '1 nota fiscal a emitir'
                  : '$_notas notas fiscais a emitir',
              subtitulo: 'Turnos concluídos sem NFS-e.',
              onTap: () => _abrir(AppRoutes.notasFiscais),
            ),
        ],
      ),
    );
  }

  /// `pushNamed` e não `pushReplacementNamed`: o usuário veio do início e
  /// precisa voltar para lá depois de resolver a pendência.
  Future<void> _abrir(String rota) async {
    await Navigator.pushNamed(context, rota);
    if (mounted) _carregar();
  }
}

class _Pendencia extends StatelessWidget {
  const _Pendencia({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
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
