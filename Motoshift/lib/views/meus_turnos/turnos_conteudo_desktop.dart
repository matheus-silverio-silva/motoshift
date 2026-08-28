import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/turno.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../presentation/providers/turno_selecionado_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/desktop/master_detail.dart';
import '../../widgets/desktop/shift_row.dart';
import '../../widgets/status_pill.dart';
import '../detalhe_turno/detalhe_turno_conteudo.dart';

/// Turnos disponíveis no desktop: master-detail com a lista à esquerda e o
/// detalhe do turno selecionado à direita.
///
/// Saiu do State da tela, que juntava este layout, o do celular, o filtro de
/// raio e a bottom sheet de filtros em 1.415 linhas.
class TurnosConteudoDesktop extends StatelessWidget {
  const TurnosConteudoDesktop({
    required this.controleRaio,
    required this.avisoLocalizacao,
    required this.porPerto,
    required this.raioKm,
    required this.hasFilters,
    required this.onAceito,
    super.key,
  });

  /// O controle de "perto de mim" — montado pela tela, que é quem tem o estado
  /// de localização. Aparece no topo da coluna da esquerda.
  final Widget controleRaio;

  /// Faixa de "não consegui sua localização", quando houver.
  final Widget? avisoLocalizacao;

  final bool porPerto;
  final double raioKm;
  final bool hasFilters;

  /// Chamado depois de aceitar um turno pelo painel da direita.
  final VoidCallback onAceito;

  /// Turnos que o motoboy já aceitou e ainda vão acontecer (ou estão
  /// acontecendo) — a mesma seleção que o celular mostra em "Meus turnos".
  List<Turno> _aceitos(TurnoProvider provider) => provider.meusTurnos.proximos();

  @override
  @override
  Widget build(BuildContext context) {
    return Consumer2<TurnoProvider, TurnoSelecionadoProvider>(
      builder: (context, provider, selecao, _) {
        final disponiveis = provider.turnosDisponiveis;
        final aceitos = _aceitos(provider);

        // A seleção é resolvida contra os disponíveis MAIS os turnos do
        // próprio motoboy. `turnosDisponiveis` perde o turno no instante em
        // que ele é aceito, então quem chega aqui redirecionado de
        // /detalhe-turno (dashboard ou histórico do desktop) apontando para um
        // turno já aceito caía no "Selecione um turno" — o detalhe do turno
        // que a pessoa está rodando não tinha como ser aberto no desktop.
        // `meusTurnos` inteiro, e não só os aceitos, para o deep-link de um
        // turno já finalizado também abrir.
        final selecionado = [...disponiveis, ...provider.meusTurnos]
            .where((t) => t.id != null && t.id == selecao.id)
            .firstOrNull;

        final total = disponiveis.length + aceitos.length;

        return MasterDetailLayout(
          listHeader: MasterDetailListHeader(
            titulo: provider.carregando
                ? 'Carregando…'
                : '$total ${total == 1 ? 'turno' : 'turnos'}',
            info: porPerto
                ? 'até ${raioKm.toStringAsFixed(0)} km'
                : (hasFilters ? 'filtros ativos' : null),
          ),
          list: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Column(
                  children: [
                    controleRaio,
                    if (avisoLocalizacao != null) ...[
                      const SizedBox(height: 12),
                      avisoLocalizacao!,
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _buildLista(
                    provider, disponiveis, aceitos, selecao),
              ),
            ],
          ),
          detail: selecionado == null
              ? const MasterDetailEmpty(
                  icon: Icons.two_wheeler_outlined,
                  titulo: 'Selecione um turno',
                  subtitulo:
                      'Escolha um turno na lista ao lado para ver horário, '
                      'raio de entrega e aceitar.',
                )
              : DetalheTurnoConteudo(
                  // A key troca junto com o turno para o estado interno
                  // (o "aceitando") não vazar de um turno para o outro.
                  key: ValueKey(selecionado.id),
                  turno: selecionado,
                  desktop: true,
                  onAceito: () {
                    selecao.limpar();
                    onAceito();
                  },
                ),
        );
      },
    );
  }

  /// Lista da esquerda do master-detail: os turnos já aceitos primeiro (são os
  /// que têm ação pendente), depois os disponíveis.
  Widget _buildLista(
    TurnoProvider provider,
    List<Turno> disponiveis,
    List<Turno> aceitos,
    TurnoSelecionadoProvider selecao,
  ) {
    if (provider.carregando) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.teal),
      );
    }
    if (disponiveis.isEmpty && aceitos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            hasFilters
                ? 'Nenhum turno encontrado com esses filtros.'
                : 'Nenhum turno disponível no momento.',
            textAlign: TextAlign.center,
            style: tsJakarta(12.5, FontWeight.w400, color: AppColors.muted),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (aceitos.isNotEmpty) ...[
          _tituloSecao('Meus turnos'),
          for (final t in aceitos) ...[
            _linhaAceita(t, selecao),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          _tituloSecao('Disponíveis'),
        ],
        if (disponiveis.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                hasFilters
                    ? 'Nenhum turno com esses filtros.'
                    : 'Nenhum turno disponível no momento.',
                textAlign: TextAlign.center,
                style:
                    tsJakarta(12, FontWeight.w400, color: AppColors.muted),
              ),
            ),
          )
        else
          for (final t in disponiveis) ...[
            _linhaDisponivel(t, selecao),
            if (t != disponiveis.last) const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _tituloSecao(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
        child: Text(
          texto.toUpperCase(),
          style: tsJakarta(10.5, FontWeight.w700, color: AppColors.muted)
              .copyWith(letterSpacing: 10.5 * .08),
        ),
      );

  Widget _linhaAceita(Turno t, TurnoSelecionadoProvider selecao) {
    final emAndamento = t.status == StatusTurno.emAndamento;
    return ShiftRow(
      horario: t.horarioFormatado,
      valor: 'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
      meta: '${t.titulo} · ${t.regiao}',
      icon: emAndamento ? Icons.schedule_outlined : Icons.two_wheeler_outlined,
      amberIcon: emAndamento,
      selected: t.id != null && t.id == selecao.id,
      pillLabel: t.status.label,
      pillVariant: emAndamento ? PillVariant.amber : PillVariant.teal,
      onTap: () => selecao.selecionar(t.id),
    );
  }

  Widget _linhaDisponivel(Turno t, TurnoSelecionadoProvider selecao) {
    return ShiftRow(
      horario: t.horarioFormatado,
      valor: 'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
      meta: '${t.titulo} · ${t.regiao} · '
          '${t.distanciaKm != null ? 'a ${t.distanciaKm!.toStringAsFixed(1).replaceAll('.', ',')} km' : '${t.raioEntregaKm.toStringAsFixed(0)} km'}',
      icon: Icons.two_wheeler_outlined,
      selected: t.id != null && t.id == selecao.id,
      pillLabel: t.multiVaga
          ? '${t.vagasRestantes} ${t.vagasRestantes == 1 ? 'vaga' : 'vagas'}'
          : t.status.label,
      pillVariant: t.multiVaga ? PillVariant.teal : PillVariant.ghost,
      // No desktop tocar num card só troca a seleção — o painel da
      // direita reage. A rota /detalhe-turno não é empilhada aqui.
      onTap: () => selecao.selecionar(t.id),
    );
  }
}
