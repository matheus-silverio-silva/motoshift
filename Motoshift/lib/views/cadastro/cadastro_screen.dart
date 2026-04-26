import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kinetic_button.dart';

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
  final _documentoCtrl = TextEditingController();

  TipoUsuario _tipo = TipoUsuario.lojista;

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _emailCtrl.dispose();
    _telefoneCtrl.dispose();
    _senhaCtrl.dispose();
    _documentoCtrl.dispose();
    super.dispose();
  }

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
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: isWide ? _buildWide(auth) : _buildMobile(auth),
    );
  }

  Widget _buildWide(AuthService auth) {
    return Row(
      children: [
        // Lado esquerdo — branding
        Expanded(
          flex: 5,
          child: _buildBrandPanel(),
        ),
        // Lado direito — formulário
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            child: _buildForm(auth),
          ),
        ),
      ],
    );
  }

  Widget _buildMobile(AuthService auth) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
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
            const SizedBox(height: 24),
            _buildForm(auth),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandPanel() {
    return Container(
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryContainer],
        ),
      ),
      padding: const EdgeInsets.all(48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Urban Kinetic',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 32,
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
          const SizedBox(height: 48),
          const Text(
            'Move with the\nspeed of the city.',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: -2,
              height: 1.1,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Junte-se à rede de logística urbana mais eficiente. Seja enviando ou entregando, otimizamos o caminho.',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 15,
              color: Colors.white.withOpacity(0.80),
              height: 1.6,
            ),
          ),
          const Spacer(),
          // Stats grid
          Row(
            children: [
              _statChip('local_shipping', '50k+', 'Deliveries Daily'),
              const SizedBox(width: 16),
              _statChip('timer', '18min', 'Avg. ETA'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon == 'local_shipping'
              ? Icons.local_shipping_outlined
              : Icons.timer_outlined,
              color: Colors.white, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Colors.white.withOpacity(0.60))),
        ],
      ),
    );
  }

  Widget _buildForm(AuthService auth) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Crie sua conta',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Preencha os dados para começar sua jornada.',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),

          // Segmented — Lojista / Motoboy
          KineticSegmentedControl<TipoUsuario>(
            items: TipoUsuario.values,
            selected: _tipo,
            labelBuilder: (t) =>
                t == TipoUsuario.lojista ? 'Lojista' : 'Motoboy',
            onChanged: (t) => setState(() => _tipo = t),
          ),
          const SizedBox(height: 28),

          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nome
                _label('Nome completo'),
                const SizedBox(height: 8),
                _field(
                  controller: _nomeCtrl,
                  hint: 'Seu nome',
                  icon: Icons.person_outline,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Informe seu nome' : null,
                ),
                const SizedBox(height: 16),

                // Email
                _label('Email corporativo'),
                const SizedBox(height: 8),
                _field(
                  controller: _emailCtrl,
                  hint: 'email@exemplo.com',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Informe o e-mail' : null,
                ),
                const SizedBox(height: 16),

                // Telefone + Senha lado a lado
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Telefone'),
                          const SizedBox(height: 8),
                          _field(
                            controller: _telefoneCtrl,
                            hint: '(11) 99999-9999',
                            icon: Icons.call_outlined,
                            keyboardType: TextInputType.phone,
                            validator: (v) => v == null || v.isEmpty
                                ? 'Informe o telefone'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Senha'),
                          const SizedBox(height: 8),
                          _field(
                            controller: _senhaCtrl,
                            hint: '••••••••',
                            icon: Icons.lock_outline,
                            obscure: true,
                            validator: (v) =>
                                v == null || v.length < 6
                                    ? 'Mínimo 6 caracteres'
                                    : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // CNPJ / CNH
                _label(_tipo == TipoUsuario.lojista ? 'CNPJ' : 'CNH'),
                const SizedBox(height: 8),
                _field(
                  controller: _documentoCtrl,
                  hint: _tipo == TipoUsuario.lojista
                      ? '00.000.000/0000-00'
                      : '00000000000',
                  icon: Icons.badge_outlined,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Documento obrigatório' : null,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 13, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'Documento obrigatório para validação da conta.',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                KineticButton(
                  label: 'Cadastrar',
                  loading: auth.carregando,
                  onPressed: _cadastrar,
                  icon: const Icon(Icons.arrow_forward,
                      color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant),
                  children: [
                    TextSpan(text: 'Já possui uma conta? '),
                    TextSpan(
                      text: 'Fazer Login',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.primary,
                      ),
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

  Widget _label(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: AppColors.onSurfaceVariant,
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(
        fontFamily: 'Manrope',
        fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.outlineVariant),
        prefixIcon: Icon(icon, color: AppColors.outline, size: 20),
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
