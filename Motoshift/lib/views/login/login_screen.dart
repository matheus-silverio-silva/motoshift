import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kinetic_button.dart';

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
  bool _lembrar = false;

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
      final tipo = auth.usuario?.tipo;
      final route = tipo == TipoUsuario.motoboy
          ? '/dashboard-motoboy'
          : '/dashboard-lojista';
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
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: isWide ? _buildWide(auth) : _buildMobile(auth),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        child: const Icon(Icons.support_agent, color: Colors.white),
      ),
    );
  }

  // ---------- Layout wide (tablet / desktop) ----------
  Widget _buildWide(AuthService auth) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.12),
              blurRadius: 64,
              offset: const Offset(0, 32),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.all(32),
        child: Row(
          children: [
            // Lado esquerdo — branding
            Expanded(
              flex: 7,
              child: _buildBrandPanel(),
            ),
            // Lado direito — formulário
            Expanded(
              flex: 5,
              child: _buildFormPanel(auth),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Layout mobile ----------
  Widget _buildMobile(AuthService auth) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            // Logo mobile
            const Text(
              'Moto Shift',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 32),
            _buildFormPanel(auth),
          ],
        ),
      ),
    );
  }

  // ---------- Painel de branding ----------
  Widget _buildBrandPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.kineticGradient,
      ),
      padding: const EdgeInsets.all(64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Urban Kinetic',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -2,
              color: Colors.white,
            ),
          ),
          Container(
            width: 48,
            height: 4,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Spacer(),
          const Text(
            'O futuro da\nlogística urbana.',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 48,
              fontWeight: FontWeight.w800,
              letterSpacing: -2,
              height: 1.1,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Conectando lojistas e motoboys com inteligência em tempo real para entregas mais rápidas e eficientes.',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.85),
              height: 1.6,
            ),
          ),
          const Spacer(),
          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STATUS',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: Colors.white.withOpacity(0.60),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Rede Operacional',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Painel de formulário ----------
  Widget _buildFormPanel(AuthService auth) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Bem-vindo',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Acesse sua conta para continuar.',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          // Seletor de tipo
          KineticSegmentedControl<TipoUsuario>(
            items: TipoUsuario.values,
            selected: _tipo,
            labelBuilder: (t) =>
                t == TipoUsuario.lojista ? 'Lojista' : 'Motoboy',
            onChanged: (t) => setState(() => _tipo = t),
          ),
          const SizedBox(height: 32),
          Form(
            key: _formKey,
            child: Column(
              children: [
                // Email
                _buildLabel('Email'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'seu@email.com',
                    prefixIcon: const Icon(Icons.mail_outline,
                        color: AppColors.outline, size: 20),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 2),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Informe o e-mail' : null,
                ),
                const SizedBox(height: 20),
                // Senha
                Row(
                  children: [
                    Expanded(child: _buildLabel('Senha')),
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text(
                        'Esqueci a senha',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _senhaCtrl,
                  obscureText: !_senhaVisivel,
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: AppColors.outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _senhaVisivel
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.outline,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _senhaVisivel = !_senhaVisivel),
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 2),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Informe a senha' : null,
                ),
                const SizedBox(height: 16),
                // Lembrar de mim
                Row(
                  children: [
                    Checkbox(
                      value: _lembrar,
                      onChanged: (v) => setState(() => _lembrar = v ?? false),
                      activeColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    const Text(
                      'Lembrar de mim',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                KineticButton(
                  label: 'Entrar',
                  loading: auth.carregando,
                  onPressed: _entrar,
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Center(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                ),
                children: [
                  const TextSpan(text: 'Não tem uma conta? '),
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: () =>
                          Navigator.pushNamed(context, '/cadastro'),
                      child: const Text(
                        'Cadastrar',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }
}
