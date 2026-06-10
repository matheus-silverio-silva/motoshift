import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';

class CnhVeiculoScreen extends StatefulWidget {
  const CnhVeiculoScreen({super.key});

  @override
  State<CnhVeiculoScreen> createState() => _CnhVeiculoScreenState();
}

class _CnhVeiculoScreenState extends State<CnhVeiculoScreen> {
  final _formKey = GlobalKey<FormState>();

  // Motoboy — apenas veículo é editável.
  // CNH (número, categoria, validade) é imutável após o cadastro — anti-fraude.
  late final TextEditingController _modeloCtrl;
  late final TextEditingController _placaCtrl;
  late final TextEditingController _anoCtrl;
  late final TextEditingController _corCtrl;

  // Lojista
  late final TextEditingController _enderecoCtrl;

  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthService>().usuario;
    _modeloCtrl = TextEditingController(text: u?.veiculoModelo ?? '');
    _placaCtrl = TextEditingController(text: u?.veiculoPlaca ?? '');
    _anoCtrl = TextEditingController(
        text: u?.veiculoAno?.toString() ?? '');
    _corCtrl = TextEditingController(text: u?.veiculoCor ?? '');
    _enderecoCtrl = TextEditingController(text: u?.enderecoComercial ?? '');
  }

  @override
  void dispose() {
    _modeloCtrl.dispose();
    _placaCtrl.dispose();
    _anoCtrl.dispose();
    _corCtrl.dispose();
    _enderecoCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final id = auth.usuario?.id;
    if (id == null) return;
    final isLojista = auth.usuario?.tipo == TipoUsuario.lojista;

    setState(() => _salvando = true);
    try {
      // CNH (número, categoria, validade) é IMUTÁVEL — não envia ao backend
      final body = isLojista
          ? {
              'enderecoComercial': _enderecoCtrl.text.trim(),
            }
          : {
              'veiculoModelo': _modeloCtrl.text.trim(),
              'veiculoPlaca':
                  _placaCtrl.text.trim().toUpperCase(),
              if (_anoCtrl.text.trim().isNotEmpty)
                'veiculoAno': int.tryParse(_anoCtrl.text.trim()),
              'veiculoCor': _corCtrl.text.trim(),
            };
      final novo = await api.atualizarPerfil(id, body);
      auth.atualizarUsuarioLocal(novo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informações salvas!'),
            backgroundColor: AppColors.good),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuario;
    final isLojista = usuario?.tipo == TipoUsuario.lojista;

    return AppScaffold(
      header: AppHeader.back(
          title: isLojista ? 'Estabelecimento' : 'CNH e Veículo'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        child: Form(
          key: _formKey,
          child: isLojista
              ? _buildLojista(usuario)
              : _buildMotoboy(usuario),
        ),
      ),
    );
  }

  Widget _buildLojista(Usuario? u) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.tealSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.storefront_outlined,
                  color: AppColors.tealDeep, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  u?.nomeFantasia ?? 'Estabelecimento',
                  style: tsJakarta(13, FontWeight.w700,
                      color: AppColors.tealDeep),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Endereço comercial',
            style:
                tsBricolage(14, FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 10),
        TextFormField(
          controller: _enderecoCtrl,
          maxLines: 3,
          style: tsJakarta(13, FontWeight.w500, color: AppColors.ink),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surface2,
            hintText: 'Av. Exemplo, 123 — Bairro, Cidade/UF',
            hintStyle: tsJakarta(13, FontWeight.w400,
                color: AppColors.muted),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.line, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.teal, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Salvar alterações',
          loading: _salvando,
          onPressed: _salvar,
        ),
      ],
    );
  }

  Widget _buildMotoboy(Usuario? u) {
    final validadeFmt = u?.cnhValidade != null
        ? DateFormat('dd/MM/yyyy', 'pt_BR').format(u!.cnhValidade!)
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('CNH',
                style: tsBricolage(14, FontWeight.w800,
                    color: AppColors.ink)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 11, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Text('Imutável',
                      style: tsJakarta(9, FontWeight.w700,
                          color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Os dados da CNH não podem ser alterados após o cadastro.',
          style: tsJakarta(11, FontWeight.w400,
              color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        _readonlyField('Número da CNH', u?.cnhNumero ?? '—'),
        _readonlyField('Categoria', u?.cnhCategoria ?? '—'),
        _readonlyField('Validade da CNH', validadeFmt),
        const SizedBox(height: 18),
        Text('Veículo',
            style:
                tsBricolage(14, FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 10),
        _field('Modelo', _modeloCtrl,
            hint: 'Ex: Honda CG 160 Titan'),
        Row(
          children: [
            Expanded(
              child: _field('Placa', _placaCtrl,
                  hint: 'ABC-1D23',
                  maxLength: 8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field('Ano', _anoCtrl,
                  keyboard: TextInputType.number, maxLength: 4),
            ),
          ],
        ),
        _field('Cor', _corCtrl, hint: 'Ex: Vermelha'),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Salvar alterações',
          loading: _salvando,
          onPressed: _salvar,
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint,
      TextInputType? keyboard,
      int? maxLength,
      String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrl,
            keyboardType: keyboard,
            maxLength: maxLength,
            style:
                tsJakarta(13, FontWeight.w500, color: AppColors.ink),
            validator: validator,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface2,
              hintText: hint,
              hintStyle:
                  tsJakarta(13, FontWeight.w400, color: AppColors.muted),
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide:
                    const BorderSide(color: AppColors.line, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide:
                    const BorderSide(color: AppColors.teal, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readonlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: tsJakarta(9, FontWeight.w700,
                  color: AppColors.muted)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(value,
                      style: tsJakarta(13, FontWeight.w500,
                          color: AppColors.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.lock_outline_rounded,
                    size: 13, color: AppColors.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
