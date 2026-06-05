import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';

class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key});

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  final _confirmarSenhaCtrl = TextEditingController();
  final _documentoCtrl = TextEditingController();

  TipoUsuario _tipo = TipoUsuario.lojista;
  bool _senhaVisivel = false;
  bool _confirmarSenhaVisivel = false;

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _emailCtrl.dispose();
    _telefoneCtrl.dispose();
    _senhaCtrl.dispose();
    _confirmarSenhaCtrl.dispose();
    _documentoCtrl.dispose();
    super.dispose();
  }

  // RF03 — validação de formato do documento federal (CNPJ/CNH)
  String? _validarDocumento(String? v) {
    if (v == null || v.isEmpty) return 'Documento obrigatório';
    final digitos = v.replaceAll(RegExp(r'\D'), '');
    if (_tipo == TipoUsuario.lojista) {
      if (digitos.length != 14) return 'CNPJ inválido — informe 14 dígitos';
    } else {
      if (digitos.length != 11) return 'CNH inválida — informe 11 dígitos';
    }
    return null;
  }

  // ── Lógica preservada do original ────────────────────────────────────────────
  Future<void> _cadastrar() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();

    final usuario = Usuario(
      nome: _nomeCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      telefone: _telefoneCtrl.text.trim(),
      tipo: _tipo,
      documentoFederal: _documentoCtrl.text.trim(),
    );

    final ok = await auth.registrar(usuario, _senhaCtrl.text);
    if (!mounted) return;

    if (ok) {
      final route = _tipo == TipoUsuario.motoboy
          ? '/dashboard-motoboy'
          : '/dashboard-lojista';
      Navigator.pushReplacementNamed(context, route);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.erro ?? 'Erro ao cadastrar'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppColors.loginBgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              children: [
                _buildTop(),
                _buildCard(auth),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTop() {
    return Padding(
      padding: const EdgeInsets.only(top: 30, bottom: 4),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xB316B5B0),
                  blurRadius: 30,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: const Icon(Icons.two_wheeler_rounded,
                color: Color(0xFFFFFFFF), size: 32),
          ),
          const SizedBox(height: 16),
          RichText(
            text: TextSpan(
              style: GoogleFonts.bricolageGrotesque(
                  fontSize: 26, fontWeight: FontWeight.w800),
              children: const [
                TextSpan(
                    text: 'Moto',
                    style: TextStyle(color: Color(0xFFFFFFFF))),
                TextSpan(
                    text: 'Shift',
                    style: TextStyle(color: AppColors.tealBright)),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Crie sua conta e comece a trabalhar.',
            style: tsJakarta(12, FontWeight.w500,
                color: const Color(0xFF8FB6B6)),
          ),
          const SizedBox(height: 26),
        ],
      ),
    );
  }

  Widget _buildCard(AuthService auth) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF7FFFFFF),
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Criar conta',
              style:
                  tsBricolage(16, FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 3),
          Text('Preencha os dados para começar.',
              style:
                  tsJakarta(11, FontWeight.w400, color: AppColors.muted)),
          const SizedBox(height: 15),
          _SegmentControl(
            value: _tipo,
            onChanged: (t) => setState(() => _tipo = t),
          ),
          const SizedBox(height: 12),
          Form(
            key: _formKey,
            child: Column(
              children: [
                _InputRow(
                  icon: Icons.person_outline_rounded,
                  hint: 'Nome completo',
                  controller: _nomeCtrl,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Informe seu nome' : null,
                ),
                const SizedBox(height: 9),
                _InputRow(
                  icon: Icons.mail_outline_rounded,
                  hint: 'E-mail',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Informe o e-mail' : null,
                ),
                const SizedBox(height: 9),
                _InputRow(
                  icon: Icons.phone_outlined,
                  hint: '(11) 99999-9999',
                  controller: _telefoneCtrl,
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.isEmpty
                      ? 'Informe o telefone'
                      : null,
                ),
                const SizedBox(height: 9),
                _InputRow(
                  icon: Icons.lock_outline_rounded,
                  hint: 'Senha',
                  controller: _senhaCtrl,
                  obscure: !_senhaVisivel,
                  suffixIcon: GestureDetector(
                    onTap: () =>
                        setState(() => _senhaVisivel = !_senhaVisivel),
                    child: Icon(
                      _senhaVisivel
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 16,
                      color: AppColors.muted,
                    ),
                  ),
                  validator: (v) => v == null || v.length < 6
                      ? 'Mínimo 6 caracteres'
                      : null,
                ),
                const SizedBox(height: 9),
                _InputRow(
                  icon: Icons.lock_outline_rounded,
                  hint: 'Confirmar senha',
                  controller: _confirmarSenhaCtrl,
                  obscure: !_confirmarSenhaVisivel,
                  suffixIcon: GestureDetector(
                    onTap: () => setState(() =>
                        _confirmarSenhaVisivel = !_confirmarSenhaVisivel),
                    child: Icon(
                      _confirmarSenhaVisivel
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 16,
                      color: AppColors.muted,
                    ),
                  ),
                  validator: (v) => v != _senhaCtrl.text
                      ? 'As senhas não coincidem'
                      : null,
                ),
                const SizedBox(height: 9),
                _InputRow(
                  icon: Icons.badge_outlined,
                  hint: _tipo == TipoUsuario.lojista
                      ? 'CNPJ (00.000.000/0000-00)'
                      : 'CNH (11 dígitos)',
                  controller: _documentoCtrl,
                  keyboardType: TextInputType.number,
                  validator: _validarDocumento,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Criar conta',
            loading: auth.carregando,
            onPressed: auth.carregando ? null : _cadastrar,
          ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: RichText(
                text: TextSpan(
                  style: tsJakarta(11, FontWeight.w400,
                      color: const Color(0xFF7FA1A1)),
                  children: [
                    const TextSpan(text: 'Já tem conta? '),
                    TextSpan(
                      text: 'Entrar',
                      style: tsJakarta(11, FontWeight.w700,
                          color: AppColors.tealBright),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Segmented control ─────────────────────────────────────────────────────────
class _SegmentControl extends StatelessWidget {
  const _SegmentControl(
      {required this.value, required this.onChanged});
  final TipoUsuario value;
  final ValueChanged<TipoUsuario> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _Seg(
            label: 'Sou Lojista',
            active: value == TipoUsuario.lojista,
            onTap: () => onChanged(TipoUsuario.lojista),
          ),
          _Seg(
            label: 'Sou Motoboy',
            active: value == TipoUsuario.motoboy,
            onTap: () => onChanged(TipoUsuario.motoboy),
          ),
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.teal : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0xB30E8B8C),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: tsJakarta(11, FontWeight.w700,
                  color:
                      active ? const Color(0xFFFFFFFF) : AppColors.muted),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Input row ─────────────────────────────────────────────────────────────────
class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.icon,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.obscure = false,
    this.suffixIcon,
    this.validator,
  });

  final IconData icon;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.teal),
          const SizedBox(width: 9),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              obscureText: obscure,
              validator: validator,
              style:
                  tsJakarta(12.5, FontWeight.w500, color: AppColors.text),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: tsJakarta(12.5, FontWeight.w400,
                    color: const Color(0xFF9AAEAE)),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                filled: false,
                suffixIcon: suffixIcon,
                suffixIconConstraints:
                    const BoxConstraints(maxWidth: 32, maxHeight: 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
