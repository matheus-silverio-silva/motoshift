import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/lancamento_gerencial.dart';
import '../../models/turno.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/formato_fiscal.dart';
import '../../widgets/app_buttons.dart';

/// Abre o formulário de lançamento gerencial — folha inferior no celular,
/// diálogo no desktop. Devolve `true` se algo foi salvo.
Future<bool> abrirFormularioDeLancamento(
  BuildContext context, {
  required List<CategoriaDeLancamento> categorias,
  required DateTime hoje,
  LancamentoGerencial? existente,
  List<Turno> turnos = const [],
}) async {
  final formulario = FormularioDeLancamento(
    categorias: categorias,
    hoje: hoje,
    existente: existente,
    turnos: turnos,
  );

  final bool? salvo;
  if (context.isDesktop) {
    salvo = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
          child: formulario,
        ),
      ),
    );
  } else {
    salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // O teclado empurra a folha para cima, em vez de cobrir o campo.
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: formulario,
      ),
    );
  }
  return salvo ?? false;
}

/// "7,50", "7.50" e "1.234,56" viram número; texto que não é número, nulo.
double? numeroDigitado(String texto) {
  var t = texto.trim().replaceAll(' ', '');
  if (t.isEmpty) return null;
  // Com vírgula, o ponto é separador de milhar.
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(t);
}

/// O formulário de um custo ou de uma receita que o usuário informa (RF13).
///
/// As categorias vêm do backend, já filtradas pelo papel: o lojista nunca vê
/// "Combustível". A tela valida o que dá para validar sem servidor — valor,
/// datas, km — e confia no backend para o resto (o turno é mesmo dele? a
/// categoria é do papel?): o erro que voltar aparece no topo do formulário.
///
/// Em "Combustível" há uma calculadora opcional: km rodados ÷ consumo (km/l)
/// × preço do litro. "Usar este valor" preenche o valor e os quilômetros —
/// é com os quilômetros que a DRE calcula o custo por km.
class FormularioDeLancamento extends StatefulWidget {
  const FormularioDeLancamento({
    required this.categorias,
    required this.hoje,
    this.existente,
    this.turnos = const [],
    super.key,
  });

  final List<CategoriaDeLancamento> categorias;
  final DateTime hoje;
  final LancamentoGerencial? existente;

  /// Turnos de que o usuário participou, para ligar o lançamento a um deles.
  final List<Turno> turnos;

  @override
  State<FormularioDeLancamento> createState() => _FormularioDeLancamentoState();
}

class _FormularioDeLancamentoState extends State<FormularioDeLancamento> {
  final _formKey = GlobalKey<FormState>();
  final _valorCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  final _calcKmCtrl = TextEditingController();
  final _calcConsumoCtrl = TextEditingController();
  final _calcPrecoCtrl = TextEditingController();

  String? _categoria;
  late DateTime _data;
  bool _recorrente = false;
  DateTime? _ate;
  int? _turnoId;

  bool _salvando = false;
  String? _erro;

  bool get _editando => widget.existente?.id != null;

  CategoriaDeLancamento? get _categoriaEscolhida {
    for (final c in widget.categorias) {
      if (c.valor == _categoria) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _data = e?.data ?? widget.hoje;
    if (e != null) {
      _categoria = widget.categorias.any((c) => c.valor == e.categoria)
          ? e.categoria
          : null;
      _valorCtrl.text = _comVirgula(e.valor, 2);
      _recorrente = e.recorrente;
      _ate = e.recorrenteAte;
      _turnoId = widget.turnos.any((t) => t.id == e.turnoId) ? e.turnoId : null;
      if (e.km != null) _kmCtrl.text = _comVirgula(e.km!, 1);
      _descricaoCtrl.text = e.descricao ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _valorCtrl,
      _kmCtrl,
      _descricaoCtrl,
      _calcKmCtrl,
      _calcConsumoCtrl,
      _calcPrecoCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _comVirgula(double v, int casas) =>
      v.toStringAsFixed(casas).replaceAll('.', ',');

  // ── Calculadora de combustível ───────────────────────────────────────────

  double? get _calculado => custoDoCombustivel(
        km: numeroDigitado(_calcKmCtrl.text),
        consumoKmPorLitro: numeroDigitado(_calcConsumoCtrl.text),
        precoDoLitro: numeroDigitado(_calcPrecoCtrl.text),
      );

  void _usarCalculado() {
    final valor = _calculado;
    final km = numeroDigitado(_calcKmCtrl.text);
    if (valor == null || km == null) return;
    setState(() {
      _valorCtrl.text = _comVirgula(valor, 2);
      _kmCtrl.text = _comVirgula(km, 1);
    });
  }

  // ── Datas ────────────────────────────────────────────────────────────────

  Future<void> _escolherData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(widget.hoje.year - 5),
      lastDate: DateTime(widget.hoje.year + 1, 12, 31),
    );
    if (escolhida == null) return;
    setState(() {
      _data = escolhida;
      // "Até" nunca fica antes do começo.
      if (_ate != null && _ate!.isBefore(_data)) _ate = null;
    });
  }

  Future<void> _escolherAte() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _ate ?? _data,
      firstDate: _data,
      lastDate: DateTime(widget.hoje.year + 10, 12, 31),
    );
    if (escolhida != null) setState(() => _ate = escolhida);
  }

  // ── Salvar ───────────────────────────────────────────────────────────────

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() => _erro = null);
    if (!_formKey.currentState!.validate()) return;

    final lancamento = LancamentoGerencial(
      categoria: _categoria!,
      valor: numeroDigitado(_valorCtrl.text)!,
      data: _data,
      recorrente: _recorrente,
      recorrenteAte: _recorrente ? _ate : null,
      turnoId: _turnoId,
      km: numeroDigitado(_kmCtrl.text),
      descricao: _descricaoCtrl.text,
    );

    final api = context.read<ApiService>().financeiro;
    final navigator = Navigator.of(context);
    setState(() => _salvando = true);
    try {
      if (_editando) {
        await api.atualizarLancamento(widget.existente!.id!, lancamento);
      } else {
        await api.criarLancamento(lancamento);
      }
      if (mounted) navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não foi possível salvar o lançamento.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  // ── Tela ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ehCombustivel = _categoriaEscolhida?.ehCombustivel ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_editando ? 'Editar lançamento' : 'Novo lançamento',
                style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(
              'Custo ou receita que não passou pela plataforma. Entra só no '
              'resultado: não mexe no seu saldo nem no extrato.',
              style: tsJakarta(12, FontWeight.w500,
                  color: AppColors.mutedTexto, height: 1.45),
            ),
            const SizedBox(height: 16),
            if (_erro != null) ...[
              _caixaDeErro(_erro!),
              const SizedBox(height: 12),
            ],
            _rotulo('Categoria'),
            DropdownButtonFormField<String>(
              key: const Key('lancamento-categoria'),
              initialValue: _categoria,
              isExpanded: true,
              decoration: _decoracao(),
              hint: const Text('Escolha'),
              items: [
                for (final c in widget.categorias)
                  DropdownMenuItem(
                    value: c.valor,
                    child: Text(
                      c.rotuloDoGrupo.isEmpty
                          ? c.rotulo
                          : '${c.rotulo} · ${c.rotuloDoGrupo}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _categoria = v),
              validator: (v) => v == null ? 'Escolha a categoria' : null,
            ),
            const SizedBox(height: 12),
            if (ehCombustivel) ...[
              _calculadora(),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rotulo('Valor (R\$)'),
                      TextFormField(
                        key: const Key('lancamento-valor'),
                        controller: _valorCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [_soNumeros],
                        decoration: _decoracao(dica: '0,00'),
                        validator: (v) {
                          final n = numeroDigitado(v ?? '');
                          if (n == null) return 'Informe o valor';
                          if (n <= 0) return 'O valor deve ser maior que zero';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rotulo(_recorrente ? 'Primeiro pagamento' : 'Data do pagamento'),
                      _botaoDeData(
                        const Key('lancamento-data'),
                        FormatoFiscal.data(_data),
                        _escolherData,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              key: const Key('lancamento-recorrente'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _recorrente,
              onChanged: (v) => setState(() {
                _recorrente = v;
                if (!v) _ate = null;
              }),
              title: Text('Repete todo mês',
                  style: tsJakarta(13, FontWeight.w700, color: AppColors.ink)),
              subtitle: Text(
                _recorrente
                    ? 'Conta uma vez por mês, no dia ${_data.day} '
                        '(ou no último dia, se o mês for mais curto).'
                    : 'Para contas fixas: celular, seguro, parcela.',
                style: tsJakarta(11.5, FontWeight.w500, color: AppColors.mutedTexto),
              ),
            ),
            if (_recorrente) ...[
              _rotulo('Até quando (opcional)'),
              Row(
                children: [
                  Expanded(
                    child: _botaoDeData(
                      const Key('lancamento-ate'),
                      _ate == null ? 'Sem data para acabar' : FormatoFiscal.data(_ate!),
                      _escolherAte,
                    ),
                  ),
                  if (_ate != null)
                    IconButton(
                      key: const Key('lancamento-ate-limpar'),
                      tooltip: 'Tirar a data final',
                      onPressed: () => setState(() => _ate = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (widget.turnos.isNotEmpty) ...[
              _rotulo('Turno (opcional)'),
              DropdownButtonFormField<int?>(
                key: const Key('lancamento-turno'),
                initialValue: _turnoId,
                isExpanded: true,
                decoration: _decoracao(),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('Nenhum turno')),
                  for (final t in widget.turnos)
                    DropdownMenuItem<int?>(
                      value: t.id,
                      child: Text(
                        '${FormatoFiscal.data(t.dataInicio)} · ${t.titulo}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _turnoId = v),
              ),
              const SizedBox(height: 12),
            ],
            _rotulo('Quilômetros rodados (opcional)'),
            TextFormField(
              key: const Key('lancamento-km'),
              controller: _kmCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_soNumeros],
              decoration: _decoracao(dica: 'Para o custo por km'),
              validator: (v) {
                if ((v ?? '').trim().isEmpty) return null;
                final n = numeroDigitado(v!);
                if (n == null || n <= 0) return 'Informe os km, ou deixe em branco';
                return null;
              },
            ),
            const SizedBox(height: 12),
            _rotulo('Descrição (opcional)'),
            TextFormField(
              key: const Key('lancamento-descricao'),
              controller: _descricaoCtrl,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoracao(dica: 'Ex.: troca de óleo'),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              key: const Key('lancamento-salvar'),
              label: _editando ? 'Salvar alterações' : 'Salvar lançamento',
              loading: _salvando,
              onPressed: _salvar,
            ),
            TextButton(
              key: const Key('lancamento-cancelar'),
              onPressed: _salvando ? null : () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.tealDeep,
                minimumSize: const Size(0, 44),
              ),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  /// km ÷ consumo × preço. Aparece só em "Combustível", e é opcional: quem
  /// tem a nota do posto digita o valor direto.
  Widget _calculadora() {
    final valor = _calculado;
    return Container(
      key: const Key('lancamento-calculadora'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Calcular pelo consumo (opcional)',
              style: tsJakarta(12.5, FontWeight.w800, color: AppColors.tealDeep)),
          const SizedBox(height: 2),
          Text('km rodados ÷ consumo (km/l) × preço do litro',
              style: tsJakarta(11, FontWeight.w500, color: AppColors.tealDeep)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _campoDaCalculadora('calc-km', 'Km rodados', _calcKmCtrl)),
              const SizedBox(width: 8),
              Expanded(
                  child: _campoDaCalculadora('calc-consumo', 'Km por litro', _calcConsumoCtrl)),
              const SizedBox(width: 8),
              Expanded(
                  child: _campoDaCalculadora('calc-preco', 'R\$ por litro', _calcPrecoCtrl)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  valor == null
                      ? 'Preencha os três campos.'
                      : 'Custo calculado: ${FormatoFiscal.moeda(valor)}',
                  key: const Key('calc-resultado'),
                  style: tsJakarta(12.5, FontWeight.w700, color: AppColors.ink),
                ),
              ),
              TextButton(
                key: const Key('calc-usar'),
                onPressed: valor == null ? null : _usarCalculado,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealDeep,
                  minimumSize: const Size(0, 44),
                ),
                child: const Text('Usar este valor'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _campoDaCalculadora(String chave, String rotulo, TextEditingController ctrl) {
    return TextField(
      key: Key(chave),
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_soNumeros],
      onChanged: (_) => setState(() {}),
      style: tsJakarta(13, FontWeight.w600, color: AppColors.ink),
      decoration: InputDecoration(
        labelText: rotulo,
        labelStyle: tsJakarta(11.5, FontWeight.w600, color: AppColors.tealDeep),
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.line),
        ),
      ),
    );
  }

  static final _soNumeros = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

  Widget _rotulo(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texto.toUpperCase(),
            style: tsJakarta(9, FontWeight.w700, color: AppColors.mutedTexto)),
      );

  InputDecoration _decoracao({String? dica}) {
    OutlineInputBorder borda(Color cor) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: cor, width: 1.5),
        );
    return InputDecoration(
      filled: true,
      fillColor: AppColors.surface2,
      isDense: true,
      hintText: dica,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: borda(AppColors.line),
      enabledBorder: borda(AppColors.line),
      focusedBorder: borda(AppColors.teal),
    );
  }

  Widget _botaoDeData(Key chave, String texto, VoidCallback onTap) {
    return OutlinedButton.icon(
      key: chave,
      onPressed: onTap,
      icon: const Icon(Icons.event_outlined, size: 17),
      label: Align(alignment: Alignment.centerLeft, child: Text(texto)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface2,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        side: const BorderSide(color: AppColors.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        textStyle: tsJakarta(13, FontWeight.w600),
      ),
    );
  }

  Widget _caixaDeErro(String mensagem) {
    return Container(
      key: const Key('lancamento-erro'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(mensagem,
                style: tsJakarta(12.5, FontWeight.w600, color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
