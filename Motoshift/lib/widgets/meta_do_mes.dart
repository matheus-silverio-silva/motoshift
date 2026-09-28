import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// "R$ 1.340 de R$ 2.000 (67%)" — a meta do mês do entregador (V19).
///
/// O ganho é o `ganhosMensais` do painel: pagamentos recebidos mais gorjetas
/// do mês, somados pelo backend. Sem meta, o card convida a definir uma — uma
/// barra zerada diria "você não ganhou nada", quando o que falta é a meta.
class MetaDoMes extends StatelessWidget {
  const MetaDoMes({
    required this.ganhos,
    required this.meta,
    required this.onEditar,
    super.key,
  });

  final double ganhos;
  final double? meta;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final m = meta;
    if (m == null || m <= 0) return _convite();

    final fracao = (ganhos / m).clamp(0.0, 1.0);
    final pct = (ganhos / m * 100).floor();
    final bateu = ganhos >= m;

    return Container(
      key: const Key('meta-do-mes'),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, size: 16, color: AppColors.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Meta do mês',
                    style: tsJakarta(12, FontWeight.w700, color: AppColors.ink)),
              ),
              TextButton(
                key: const Key('meta-editar'),
                onPressed: onEditar,
                // 44 px de altura, o alvo mínimo de toque do app.
                style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
                child: const Text('Alterar'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${reaisSemCentavos(ganhos)} de ${reaisSemCentavos(m)} ($pct%)',
                  key: const Key('meta-progresso'),
                  style: tsBricolage(15, FontWeight.w800, color: AppColors.ink),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: fracao,
                    minHeight: 8,
                    backgroundColor: AppColors.surface2,
                    color: bateu ? AppColors.good : AppColors.teal,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  bateu
                      ? 'Meta batida. Pagamentos recebidos e gorjetas do mês.'
                      : 'Faltam ${reaisSemCentavos(m - ganhos)}. Pagamentos '
                          'recebidos e gorjetas do mês.',
                  style: tsJakarta(10.5, FontWeight.w400, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _convite() {
    return Container(
      key: const Key('meta-convite'),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_outlined, size: 18, color: AppColors.tealDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Quanto você quer ganhar este mês? Defina uma meta e acompanhe '
              'aqui.',
              style: tsJakarta(11.5, FontWeight.w600,
                  color: AppColors.tealDeep, height: 1.4),
            ),
          ),
          TextButton(
            key: const Key('meta-definir'),
            onPressed: onEditar,
            // 44 px de altura, o alvo mínimo de toque do app.
            style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
            child: const Text('Definir meta'),
          ),
        ],
      ),
    );
  }
}

/// "R$ 1.340" — milhar com ponto, sem centavos.
String reaisSemCentavos(double v) {
  final inteiro = v.round().abs().toString();
  final comPontos = inteiro.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  return '${v < 0 ? '-' : ''}R\$ $comPontos';
}

/// Abre o diálogo da meta e grava no perfil. Devolve a meta nova (ou nula,
/// se foi tirada), ou `false` se a pessoa desistiu ou deu erro.
Future<Object?> editarMetaDoMes(BuildContext context) async {
  final auth = context.read<AuthService>();
  final api = context.read<ApiService>();
  final atual = auth.usuario?.metaMensal;

  final resultado = await showDialog<Object?>(
    context: context,
    builder: (_) => _DialogoDaMeta(atual: atual),
  );
  if (resultado == null) return false;

  final id = auth.usuario?.id;
  if (id == null) return false;
  final meta = resultado == 'tirar' ? null : resultado as double;
  try {
    final novo = await api.auth.atualizarPerfil(id, {'metaMensal': meta});
    auth.atualizarUsuarioLocal(novo);
    return meta;
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    }
    return false;
  }
}

/// O diálogo é dono do seu campo: o controller vive e morre com ele. Criado
/// e descartado por quem abre o diálogo, ele sumia enquanto a animação de
/// fechar ainda o desenhava.
class _DialogoDaMeta extends StatefulWidget {
  const _DialogoDaMeta({this.atual});

  final double? atual;

  @override
  State<_DialogoDaMeta> createState() => _DialogoDaMetaState();
}

class _DialogoDaMetaState extends State<_DialogoDaMeta> {
  late final TextEditingController _ctrl = TextEditingController(
      text: widget.atual == null ? '' : widget.atual!.toStringAsFixed(0));
  String? _erro;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _salvar() {
    final v = double.tryParse(
        _ctrl.text.replaceAll('.', '').replaceAll(',', '.').trim());
    if (v == null || v <= 0 || v > 100000) {
      setState(() => _erro = 'Informe um valor entre R\$ 1 e R\$ 100.000.');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Meta do mês',
          style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quanto você quer ganhar no mês, somando pagamentos e gorjetas.',
            style:
                tsJakarta(12, FontWeight.w400, color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('meta-valor'),
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (_) => _salvar(),
            decoration: InputDecoration(
              prefixText: 'R\$ ',
              hintText: '2000',
              errorText: _erro,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.atual != null)
          TextButton(
            key: const Key('meta-tirar'),
            onPressed: () => Navigator.pop(context, 'tirar'),
            child: Text('Tirar meta',
                style: tsJakarta(13, FontWeight.w600, color: AppColors.error)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancelar',
              style: tsJakarta(13, FontWeight.w600, color: AppColors.muted)),
        ),
        FilledButton(
          key: const Key('meta-salvar'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
          onPressed: _salvar,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
