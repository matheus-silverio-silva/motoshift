import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Gorjeta opcional na avaliação do entregador: sem gorjeta, R$ 5, R$ 10,
/// R$ 20 ou outro valor.
///
/// Devolve o valor escolhido por [onMudou] — `null` é "sem gorjeta", e é o
/// padrão: gorjeta é gesto, não etapa do formulário. O teto ([maximo]) é o
/// mesmo do backend (`motoshift.gorjeta.maximo`, padrão R$ 50); o backend
/// confere de novo, e a mensagem dele é a que vale.
class SeletorDeGorjeta extends StatefulWidget {
  const SeletorDeGorjeta({
    required this.onMudou,
    this.maximo = 50,
    this.compacto = false,
    super.key,
  });

  final ValueChanged<double?> onMudou;
  final double maximo;

  /// Sem a caixa em volta — para caber no card de cada entregador.
  final bool compacto;

  @override
  State<SeletorDeGorjeta> createState() => _SeletorDeGorjetaState();
}

class _SeletorDeGorjetaState extends State<SeletorDeGorjeta> {
  static const _sugestoes = [5.0, 10.0, 20.0];

  /// null = sem gorjeta; -1 = "outro valor".
  double? _escolha;
  final _outroCtrl = TextEditingController();
  String? _erroOutro;

  @override
  void dispose() {
    _outroCtrl.dispose();
    super.dispose();
  }

  void _escolher(double? v) {
    setState(() {
      _escolha = v;
      _erroOutro = null;
    });
    if (v == -1) {
      _aoDigitar(_outroCtrl.text);
    } else {
      widget.onMudou(v);
    }
  }

  void _aoDigitar(String texto) {
    final v = double.tryParse(texto.replaceAll(',', '.').trim());
    String? erro;
    double? valor;
    if (texto.trim().isEmpty) {
      valor = null;
    } else if (v == null || v < 1) {
      erro = 'A gorjeta é de pelo menos R\$ 1,00.';
    } else if (v > widget.maximo) {
      erro = 'A gorjeta vai até R\$ ${widget.maximo.toStringAsFixed(0)}.';
    } else {
      valor = double.parse(v.toStringAsFixed(2));
    }
    setState(() => _erroOutro = erro);
    widget.onMudou(erro == null ? valor : null);
  }

  @override
  Widget build(BuildContext context) {
    final conteudo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.volunteer_activism_outlined,
                size: 15, color: AppColors.teal),
            const SizedBox(width: 6),
            Text('Gorjeta (opcional)',
                style: tsJakarta(11, FontWeight.w700, color: AppColors.ink)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Sai do seu saldo disponível e vai direto para a carteira do '
          'entregador.',
          style: tsJakarta(10.5, FontWeight.w400,
              color: AppColors.muted, height: 1.35),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip('Sem gorjeta', null, const Key('gorjeta-nenhuma')),
            for (final v in _sugestoes)
              _chip('R\$ ${v.toStringAsFixed(0)}', v,
                  Key('gorjeta-${v.toStringAsFixed(0)}')),
            _chip('Outro valor', -1, const Key('gorjeta-outro')),
          ],
        ),
        if (_escolha == -1) ...[
          const SizedBox(height: 10),
          TextField(
            key: const Key('gorjeta-outro-valor'),
            controller: _outroCtrl,
            onChanged: _aoDigitar,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: tsJakarta(13, FontWeight.w600, color: AppColors.ink),
            decoration: InputDecoration(
              prefixText: 'R\$ ',
              hintText: '0,00',
              errorText: _erroOutro,
              isDense: true,
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.line),
              ),
            ),
          ),
        ],
      ],
    );

    if (widget.compacto) return conteudo;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: conteudo,
    );
  }

  Widget _chip(String rotulo, double? valor, Key key) {
    final sel = _escolha == valor;
    return GestureDetector(
      key: key,
      onTap: () => _escolher(valor),
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: sel ? AppColors.teal : AppColors.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: sel ? AppColors.teal : AppColors.line, width: 1.5),
        ),
        child: Text(rotulo,
            style: tsJakarta(11.5, FontWeight.w700,
                color: sel ? Colors.white : AppColors.muted)),
      ),
    );
  }
}
