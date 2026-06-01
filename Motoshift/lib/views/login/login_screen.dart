import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  TipoUsuario _tipo = TipoUsuario.lojista;
  bool _senhaVisivel = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    final ok = await auth.login(_emailCtrl.text.trim(), _senhaCtrl.text, _tipo);
    if (!mounted) return;
    if (ok) {
      final route = auth.usuario?.tipo == TipoUsuario.motoboy
          ? AppRoutes.dashboardMotoboy
          : AppRoutes.dashboardLojista;
      Navigator.pushReplacementNamed(context, route);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.erro ?? 'Erro ao fazer login'),
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
        decoration: const BoxDecoration(gradient: AppColors.loginBgGradient),
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
          // Logo
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
            'Turnos organizados. Renda previsível.',
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
          Text('Bem-vindo de volta',
              style: tsBricolage(16, FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 3),
          Text('Entre para acessar seus turnos',
              style: tsJakarta(11, FontWeight.w400, color: AppColors.muted)),
          const SizedBox(height: 15),
          // Segmented control
          _SegmentControl(
            value: _tipo,
            onChanged: (t) => setState(() => _tipo = t),
          ),
          const SizedBox(height: 4),
          Form(
            key: _formKey,
            child: Column(
              children: [
                // E-mail
                _InputRow(
                  icon: Icons.mail_outline_rounded,
                  hint: 'E-mail',
                  value: _emailCtrl.text,
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Informe o e-mail' : null,
                ),
                const SizedBox(height: 9),
                // Senha
                _InputRow(
                  icon: Icons.lock_outline_rounded,
                  hint: '••••••••',
                  value: _senhaCtrl.text,
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
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Informe a senha' : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () =>
                  Navigator.pushNamed(context, AppRoutes.esqueceuSenha),
              child: Text('Esqueci minha senha',
                  style: tsJakarta(10.5, FontWeight.w700,
                      color: AppColors.teal)),
            ),
          ),
          const SizedBox(height: 14),
          // Botão entrar
          GestureDetector(
            onTap: auth.carregando ? null : _entrar,
            child: Container(
              width: double.infinity,
              height: 46,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xCC0E8B8C),
                    blurRadius: 22,
                    spreadRadius: -10,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Center(
                child: auth.carregando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Entrar',
                              style: tsJakarta(13.5, FontWeight.w700,
                                  color: const Color(0xFFFFFFFF))),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded,
                              color: Color(0xFFFFFFFF), size: 15),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, AppRoutes.cadastro),
              child: RichText(
                text: TextSpan(
                  style: tsJakarta(11, FontWeight.w400,
                      color: const Color(0xFF7FA1A1)),
                  children: [
                    const TextSpan(text: 'Ainda não tem conta? '),
                    TextSpan(
                      text: 'Criar agora',
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
  const _SegmentControl({required this.value, required this.onChanged});
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
                    )
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: tsJakarta(11, FontWeight.w700,
                  color: active ? const Color(0xFFFFFFFF) : AppColors.muted),
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
    required this.value,
    required this.controller,
    this.keyboardType,
    this.obscure = false,
    this.suffixIcon,
    this.validator,
  });

  final IconData icon;
  final String hint;
  final String value;
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
              style: tsJakarta(12.5, FontWeight.w500, color: AppColors.text),
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
