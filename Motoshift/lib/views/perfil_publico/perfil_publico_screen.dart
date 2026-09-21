import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/perfil_publico.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/iniciais.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/empty_state.dart';

/// O perfil de outra conta — o que a plataforma mostra de quem está do outro
/// lado do turno.
///
/// <h3>Por que esta tela existe</h3>
/// O detalhe do turno tinha um botão "Contatar" com `onTap: () {}`. A saída
/// óbvia seria abrir o telefone do entregador, mas o
/// `PerfilPublicoResponse` do backend **não devolve telefone nem e-mail**, e
/// não por esquecimento: o javadoc registra que a rota antes devolvia CPF, CNH
/// e endereço para qualquer token válido, e que isso foi cortado por LGPD.
/// Expor o telefone só para alimentar um botão desfaria essa decisão pela
/// porta dos fundos. O botão virou "Ver perfil", e mostra o que a plataforma
/// já decidiu que é público.
class PerfilPublicoArgs {
  const PerfilPublicoArgs({required this.usuarioId, this.nome});

  final int usuarioId;

  /// Nome já conhecido por quem abriu, para o cabeçalho não piscar enquanto
  /// a requisição não volta.
  final String? nome;
}

class PerfilPublicoScreen extends StatefulWidget {
  const PerfilPublicoScreen({super.key});

  @override
  State<PerfilPublicoScreen> createState() => _PerfilPublicoScreenState();
}

class _PerfilPublicoScreenState extends State<PerfilPublicoScreen> {
  PerfilPublico? _perfil;
  bool _carregando = true;
  String? _erro;

  PerfilPublicoArgs? get _args =>
      ModalRoute.of(context)?.settings.arguments as PerfilPublicoArgs?;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final args = _args;
    if (args == null) {
      setState(() {
        _carregando = false;
        _erro = 'Perfil não informado.';
      });
      return;
    }
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final p =
          await context.read<ApiService>().usuarios.buscarPerfilPublico(
                args.usuarioId,
              );
      if (mounted) setState(() => _perfil = p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não foi possível abrir o perfil.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = _perfil?.nomeDeExibicao ?? _args?.nome ?? 'Perfil';
    return AdaptiveScaffold(
      header: AppHeader.back(title: titulo),
      desktopTitle: titulo,
      desktopSubtitle: _perfil?.ehLojista == true
          ? 'Perfil do estabelecimento'
          : 'Perfil do entregador',
      body: _conteudo(),
      desktopBody: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _conteudo(),
        ),
      ),
    );
  }

  Widget _conteudo() {
    if (_carregando) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
      );
    }
    if (_erro != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: EmptyState(
          icon: Icons.person_off_outlined,
          titulo: 'Perfil indisponível',
          subtitulo: _erro!,
          acaoLabel: 'Tentar novamente',
          onAcao: _carregar,
        ),
      );
    }

    final p = _perfil!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
      children: [
        _cabecalho(p),
        const SizedBox(height: 18),
        if (p.localidade != null)
          _linha(Icons.place_outlined, 'Cidade', p.localidade!),
        if (p.veiculo != null)
          _linha(Icons.two_wheeler_outlined, 'Veículo', p.veiculo!),
        if (p.score != null)
          _linha(Icons.shield_outlined, 'Reputação',
              '${p.score!.toStringAsFixed(1).replaceAll('.', ',')} / 5'),
        const SizedBox(height: 18),
        _avisoDePrivacidade(),
      ],
    );
  }

  Widget _cabecalho(PerfilPublico p) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.tealSoft,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(
            child: Text(
              iniciaisDe(p.nomeDeExibicao),
              style: tsBricolage(26, FontWeight.w800, color: AppColors.tealDeep),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(p.nomeDeExibicao,
            textAlign: TextAlign.center,
            style: tsBricolage(19, FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        if (p.mediaAvaliacao != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star_rounded, size: 16, color: AppColors.amber),
              const SizedBox(width: 4),
              Text(
                p.mediaAvaliacao!.toStringAsFixed(1).replaceAll('.', ','),
                style: tsJakarta(12.5, FontWeight.w700, color: AppColors.text),
              ),
            ],
          )
        else
          Text('Ainda sem avaliações',
              style: tsJakarta(12, FontWeight.w400, color: AppColors.muted)),
      ],
    );
  }

  Widget _linha(IconData icone, String rotulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icone, size: 18, color: AppColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(rotulo,
                  style:
                      tsJakarta(12, FontWeight.w500, color: AppColors.muted)),
            ),
            Text(valor,
                style: tsJakarta(12.5, FontWeight.w700, color: AppColors.text)),
          ],
        ),
      ),
    );
  }

  /// Diz por que não há telefone aqui, em vez de deixar o usuário procurar.
  Widget _avisoDePrivacidade() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 17, color: AppColors.muted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Telefone, e-mail e documentos não são exibidos a outras contas. '
              'O contato durante o turno é feito pela plataforma.',
              style: tsJakarta(11.5, FontWeight.w400,
                  color: AppColors.muted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
