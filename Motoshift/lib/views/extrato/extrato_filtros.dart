import 'package:flutter/material.dart';

import '../../models/extrato_filtro.dart';
import '../../models/transacao.dart';
import '../../theme/app_theme.dart';

/// A folha de filtros do extrato.
///
/// Edita uma cópia e só devolve o filtro no "Aplicar": mexer no filtro ativo a
/// cada toque dispararia uma consulta por clique, e o usuário que abriu para
/// mudar três coisas veria a lista piscar três vezes.
class ExtratoFiltros extends StatefulWidget {
  const ExtratoFiltros({required this.inicial, required this.hoje, super.key});

  final ExtratoFiltro inicial;
  final DateTime hoje;

  @override
  State<ExtratoFiltros> createState() => _ExtratoFiltrosState();
}

class _ExtratoFiltrosState extends State<ExtratoFiltros> {
  late ExtratoFiltro _rascunho;
  late final TextEditingController _busca;

  @override
  void initState() {
    super.initState();
    _rascunho = widget.inicial;
    _busca = TextEditingController(text: widget.inicial.busca ?? '');
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  void _aplicarAtalho(AtalhoDePeriodo atalho) {
    final (de, ate) = atalho.intervalo(widget.hoje);
    setState(() => _rascunho = _rascunho.copyWith(
          dataInicio: de,
          dataFim: ate,
          atalho: atalho,
        ));
  }

  Future<void> _escolherPeriodo() async {
    final intervalo = await showDateRangePicker(
      context: context,
      firstDate: DateTime(widget.hoje.year - 3),
      lastDate: widget.hoje,
      initialDateRange: _rascunho.dataInicio != null && _rascunho.dataFim != null
          ? DateTimeRange(
              start: _rascunho.dataInicio!, end: _rascunho.dataFim!)
          : null,
    );
    if (intervalo == null) return;
    setState(() => _rascunho = _rascunho.copyWith(
          dataInicio: intervalo.start,
          dataFim: intervalo.end,
          // Datas escolhidas à mão: nenhum atalho fica marcado.
          limparPeriodo: false,
        ).copyWith(atalho: null));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                children: [
                  Text('Filtrar extrato',
                      style: tsBricolage(18, FontWeight.w800,
                          color: AppColors.ink)),
                  const SizedBox(height: 18),
                  _secao('Período'),
                  _atalhosDePeriodo(),
                  const SizedBox(height: 8),
                  _botaoDePeriodoPersonalizado(),
                  const SizedBox(height: 20),
                  _secao('Entrada ou saída'),
                  _escolhaDeNatureza(),
                  const SizedBox(height: 20),
                  _secao('Tipo de lançamento'),
                  _escolhaDeTipos(),
                  const SizedBox(height: 20),
                  _secao('Buscar na descrição'),
                  TextField(
                    key: const Key('filtro-busca'),
                    controller: _busca,
                    decoration: InputDecoration(
                      hintText: 'Ex.: Pizzaria',
                      filled: true,
                      fillColor: AppColors.surface2,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _rodape(),
          ],
        ),
      ),
    );
  }

  Widget _secao(String titulo) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(titulo,
            style: tsJakarta(12, FontWeight.w700, color: AppColors.text)),
      );

  Widget _atalhosDePeriodo() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in AtalhoDePeriodo.values)
          ChoiceChip(
            key: Key('filtro-periodo-${a.name}'),
            label: Text(a.label),
            selected: _rascunho.atalho == a,
            onSelected: (_) => _aplicarAtalho(a),
          ),
      ],
    );
  }

  Widget _botaoDePeriodoPersonalizado() {
    final de = _rascunho.dataInicio;
    final ate = _rascunho.dataFim;
    final rotulo = (de == null || ate == null)
        ? 'Personalizado'
        : '${_data(de)} a ${_data(ate)}';
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('filtro-periodo-personalizado'),
            onPressed: _escolherPeriodo,
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: Text(rotulo, overflow: TextOverflow.ellipsis),
          ),
        ),
        if (de != null || ate != null)
          IconButton(
            tooltip: 'Limpar período',
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(
                () => _rascunho = _rascunho.copyWith(limparPeriodo: true)),
          ),
      ],
    );
  }

  Widget _escolhaDeNatureza() {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          key: const Key('filtro-natureza-credito'),
          label: const Text('Entradas'),
          selected: _rascunho.natureza == NaturezaTransacao.credito,
          onSelected: (sel) => setState(() => _rascunho = sel
              ? _rascunho.copyWith(natureza: NaturezaTransacao.credito)
              : _rascunho.copyWith(limparNatureza: true)),
        ),
        ChoiceChip(
          key: const Key('filtro-natureza-debito'),
          label: const Text('Saídas'),
          selected: _rascunho.natureza == NaturezaTransacao.debito,
          onSelected: (sel) => setState(() => _rascunho = sel
              ? _rascunho.copyWith(natureza: NaturezaTransacao.debito)
              : _rascunho.copyWith(limparNatureza: true)),
        ),
      ],
    );
  }

  Widget _escolhaDeTipos() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in TipoTransacao.filtraveis)
          FilterChip(
            key: Key('filtro-tipo-${t.name}'),
            label: Text(t.label),
            selected: _rascunho.tipos.contains(t),
            onSelected: (sel) {
              final tipos = Set<TipoTransacao>.from(_rascunho.tipos);
              sel ? tipos.add(t) : tipos.remove(t);
              setState(() => _rascunho = _rascunho.copyWith(tipos: tipos));
            },
          ),
      ],
    );
  }

  Widget _rodape() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                key: const Key('filtro-limpar'),
                onPressed: () => setState(() {
                  _rascunho = const ExtratoFiltro();
                  _busca.clear();
                }),
                child: const Text('Limpar tudo'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const Key('filtro-aplicar'),
                onPressed: () => Navigator.of(context).pop(
                  _rascunho.copyWith(busca: _busca.text.trim()),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: AppColors.teal,
                ),
                child: const Text('Aplicar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _data(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
