import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';

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
          clock.now().subtract(const Duration(days: 365 * 30)),
      firstDate: DateTime(1930),
      lastDate: clock.now(),
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
      final novo = await api.auth.atualizarPerfil(id, {
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

    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Dados pessoais'),
      desktopTitle: 'Dados pessoais',
      desktopSubtitle: isLojista
          ? 'O CNPJ não muda depois do cadastro'
          : 'A CNH não muda depois do cadastro',
      // Sub-página do Perfil: mantém "Perfil" aceso na sidebar em vez de
      // deixar o desktop sem nenhum item destacado.
      desktopSelectedRoute: AppRoutes.perfil,
      desktopBody: _buildDesktop(usuario, isLojista),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section('Informações pessoais'),
              const SizedBox(height: 10),
              ..._camposPessoais(usuario, isLojista),
              const SizedBox(height: 18),
              _section('Endereço'),
              const SizedBox(height: 10),
              ..._camposEndereco(),
              if (isLojista) ...[
                const SizedBox(height: 18),
                _section('Estabelecimento'),
                const SizedBox(height: 10),
                _campoEstabelecimento(),
              ],
              const SizedBox(height: 24),
              _botaoSalvar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Campos — uma definição só, montada de dois jeitos ─────────────────────

  List<Widget> _camposPessoais(Usuario? usuario, bool isLojista) => [
        _field('Nome completo', _nomeCtrl, validator: Validators.nome),
        _readonlyField('E-mail', usuario?.email ?? ''),
        _field('Telefone', _telefoneCtrl,
            keyboard: TextInputType.phone, validator: Validators.telefone),
        // CNPJ/CNH são imutáveis após o cadastro (anti-fraude)
        _readonlyField(
            isLojista ? 'CNPJ' : 'CNH', usuario?.documentoFederal ?? '—'),
        _dateField('Data de nascimento', _dataNascimento, _pickData),
      ];

  List<Widget> _camposEndereco() => [
        _field('Cidade', _cidadeCtrl),
        _field('Estado (UF)', _estadoCtrl, maxLength: 2, validator: (v) {
          if (v != null && v.isNotEmpty && v.length != 2) {
            return 'Use 2 letras (UF)';
          }
          return null;
        }),
      ];

  Widget _campoEstabelecimento() =>
      _field('Nome fantasia', _nomeFantasiaCtrl);

  Widget _botaoSalvar() => PrimaryButton(
        label: 'Salvar alterações',
        loading: _salvando,
        onPressed: _salvar,
      );

  // ── Desktop — o formulário em duas colunas, dentro do shell ───────────────

  Widget _buildDesktop(Usuario? usuario, bool isLojista) {
    return Form(
      key: _formKey,
      child: ContentGrid(
        children: [
          GridCol(
            span: 7,
            child: PanelCard(
              title: 'Informações pessoais',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _camposPessoais(usuario, isLojista),
              ),
            ),
          ),
          GridCol(
            span: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PanelCard(
                  title: 'Endereço',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _camposEndereco(),
                  ),
                ),
                if (isLojista) ...[
                  const SizedBox(height: 16),
                  PanelCard(
                    title: 'Estabelecimento',
                    child: _campoEstabelecimento(),
                  ),
                ],
                const SizedBox(height: 16),
                _botaoSalvar(),
              ],
            ),
          ),
        ],
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
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)),
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

  Widget _dateField(
      String label, DateTime? value, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 8),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(11),
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
                      size: 15, color: AppColors.teal),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
