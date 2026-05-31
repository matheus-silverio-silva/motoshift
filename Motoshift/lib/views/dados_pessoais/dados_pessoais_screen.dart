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

class DadosPessoaisScreen extends StatefulWidget {
  const DadosPessoaisScreen({super.key});

  @override
  State<DadosPessoaisScreen> createState() => _DadosPessoaisScreenState();
}

class _DadosPessoaisScreenState extends State<DadosPessoaisScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _telefoneCtrl;
  late final TextEditingController _cidadeCtrl;
  late final TextEditingController _estadoCtrl;
  late final TextEditingController _nomeFantasiaCtrl;
  DateTime? _dataNascimento;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthService>().usuario;
    _nomeCtrl = TextEditingController(text: u?.nome ?? '');
    _telefoneCtrl = TextEditingController(text: u?.telefone ?? '');
    _cidadeCtrl = TextEditingController(text: u?.cidade ?? '');
    _estadoCtrl = TextEditingController(text: u?.estado ?? '');
    _nomeFantasiaCtrl =
        TextEditingController(text: u?.nomeFantasia ?? '');
    _dataNascimento = u?.dataNascimento;
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _telefoneCtrl.dispose();
    _cidadeCtrl.dispose();
    _estadoCtrl.dispose();
    _nomeFantasiaCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickData() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataNascimento ??
          DateTime.now().subtract(const Duration(days: 365 * 30)),
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dataNascimento = picked);
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final id = auth.usuario?.id;
    if (id == null) return;

    setState(() => _salvando = true);
    try {
      final novo = await api.atualizarPerfil(id, {
        'nome': _nomeCtrl.text.trim(),
        'telefone': _telefoneCtrl.text.trim(),
        'cidade': _cidadeCtrl.text.trim(),
        'estado': _estadoCtrl.text.trim().toUpperCase(),
        if (_dataNascimento != null)
          'dataNascimento':
              _dataNascimento!.toIso8601String().substring(0, 10),
        if (auth.usuario?.tipo == TipoUsuario.lojista)
          'nomeFantasia': _nomeFantasiaCtrl.text.trim(),
      });
      auth.atualizarUsuarioLocal(novo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Dados atualizados com sucesso!'),
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
      header: AppHeader.back(title: 'Dados pessoais'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section('Informações pessoais'),
              const SizedBox(height: 10),
              _field('Nome completo', _nomeCtrl,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Informe o nome' : null),
              _readonlyField('E-mail', usuario?.email ?? ''),
              _field('Telefone', _telefoneCtrl,
                  keyboard: TextInputType.phone,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Informe o telefone' : null),
              _readonlyField(
                  isLojista ? 'CNPJ' : 'CNH',
                  usuario?.documentoFederal ?? '—'),
              _dateField('Data de nascimento', _dataNascimento, _pickData),
              const SizedBox(height: 18),
              _section('Endereço'),
              const SizedBox(height: 10),
              _field('Cidade', _cidadeCtrl),
              _field('Estado (UF)', _estadoCtrl,
                  maxLength: 2,
                  validator: (v) {
                    if (v != null && v.isNotEmpty && v.length != 2) {
                      return 'Use 2 letras (UF)';
                    }
                    return null;
                  }),
              if (isLojista) ...[
                const SizedBox(height: 18),
                _section('Estabelecimento'),
                const SizedBox(height: 10),
                _field('Nome fantasia', _nomeFantasiaCtrl),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Salvar alterações',
                loading: _salvando,
                onPressed: _salvar,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String text) => Text(
        text,
        style:
            tsBricolage(14, FontWeight.w800, color: AppColors.ink),
      );

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType? keyboard,
      int? maxLength,
      String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 6),
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
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
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
        ],
      ),
    );
  }

  Widget _readonlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(value,
                      style: tsJakarta(13, FontWeight.w500,
                          color: AppColors.muted)),
                ),
                const Icon(Icons.lock_outline_rounded,
                    size: 13, color: AppColors.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateField(
      String label, DateTime? value, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line, width: 1.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value != null
                          ? DateFormat('dd/MM/yyyy', 'pt_BR').format(value)
                          : 'Selecionar',
                      style: tsJakarta(13, FontWeight.w500,
                          color: value != null
                              ? AppColors.ink
                              : AppColors.muted),
                    ),
                  ),
                  const Icon(Icons.calendar_today_outlined,
                      size: 14, color: AppColors.teal),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
