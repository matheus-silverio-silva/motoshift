import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/campo_de_senha.dart';

/// O e-mail digitado no login, para a tela não pedir de novo o que a pessoa
/// acabou de escrever.
class RecuperarSenhaArgs {
  const RecuperarSenhaArgs({this.email});

  final String? email;
}

enum _Etapa { email, codigo, senha }

/// Rota `/esqueceu-senha`: e-mail → código → senha nova (SCRUM-32).
///
/// <h3>O que mudou e por quê</h3>
/// Esta tela só orientava: dizia que a redefinição não era automática e
/// mandava procurar a equipe. Agora ela É a redefinição, em três passos:
///
/// 1. **E-mail.** O app pede o código (`POST /api/auth/esqueci-senha`). O
///    backend responde igual exista ou não a conta, então a tela nunca diz
///    "e-mail não cadastrado" — diz "se houver uma conta, enviamos".
/// 2. **Código.** Os 6 dígitos que chegaram por e-mail. O envio é simulado
///    nesta versão (o código sai no log do servidor), e a tela avisa: sem o
///    aviso, quem testa ficaria esperando um e-mail que não vem.
/// 3. **Senha nova.** Só aqui o app chama o backend de novo
///    (`POST /api/auth/redefinir-senha`), com e-mail + código + senha. Não há
///    rota para conferir o código sozinho — cada conferência gasta uma das
///    cinco tentativas dele, e gastar uma só para avançar de tela seria
///    desperdício. Se o código estiver errado, a tela volta ao passo 2 com a
///    mensagem, e a senha digitada fica guardada.
///
/// Redefinir a senha também destrava a conta bloqueada por tentativas de
/// login: quem recebeu o código provou que é o dono.
class RecuperarSenhaScreen extends StatefulWidget {
  const RecuperarSenhaScreen({
    this.esperaParaReenviar = const Duration(seconds: 60),
    super.key,
  });

  /// Quanto tempo o "Reenviar código" fica desligado depois de um envio. É o
  /// mesmo intervalo que o backend impõe entre dois códigos da mesma conta
  /// (`SenhaService.INTERVALO_ENTRE_CODIGOS_SEGUNDOS`): antes disso o pedido
  /// seria aceito e ignorado, e o botão prometeria um e-mail que não sai.
  final Duration esperaParaReenviar;

  @override
  State<RecuperarSenhaScreen> createState() => _RecuperarSenhaScreenState();
}

class _RecuperarSenhaScreenState extends State<RecuperarSenhaScreen> {
  final _formEmail = GlobalKey<FormState>();
  final _formCodigo = GlobalKey<FormState>();
  final _formSenha = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final _novaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();

  _Etapa _etapa = _Etapa.email;
  bool _enviando = false;
  bool _leuArgumentos = false;

  /// O que o servidor disse do código ("Código inválido ou expirado...").
  String? _erroDoCodigo;

  bool _podeReenviar = false;
  Timer? _esperaDoReenvio;

  /// O e-mail como vai para o backend — e como aparece no passo 2.
  String get _email => Validators.normalizarEmail(_emailCtrl.text);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_leuArgumentos) return;
    _leuArgumentos = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is RecuperarSenhaArgs && (args.email ?? '').trim().isNotEmpty) {
      _emailCtrl.text = args.email!.trim();
    }
  }

  @override
  void dispose() {
    _esperaDoReenvio?.cancel();
    _emailCtrl.dispose();
    _codigoCtrl.dispose();
    _novaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  // ── Ações ────────────────────────────────────────────────────────────────

  /// Passo 1 → 2, e também o "Reenviar código" do passo 2.
  Future<void> _pedirCodigo() async {
    if (_enviando) return;
    if (_etapa == _Etapa.email && !_formEmail.currentState!.validate()) return;

    final api = context.read<ApiService>();
    final reenvio = _etapa == _Etapa.codigo;

    setState(() => _enviando = true);
    try {
      await api.auth.esqueciSenha(_email);
      if (!mounted) return;
      setState(() {
        _etapa = _Etapa.codigo;
        _erroDoCodigo = null;
        if (reenvio) _codigoCtrl.clear();
      });
      _comecarEsperaDoReenvio();
      if (reenvio) _avisar('Pedimos outro código. O anterior deixa de valer.');
    } on ApiException catch (e) {
      if (mounted) _avisar(e.message, erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _comecarEsperaDoReenvio() {
    _esperaDoReenvio?.cancel();
    setState(() => _podeReenviar = false);
    _esperaDoReenvio = Timer(widget.esperaParaReenviar, () {
      if (mounted) setState(() => _podeReenviar = true);
    });
  }

  /// Passo 2 → 3. Só confere o formato: quem confere o código é o backend,
  /// junto com a senha nova.
  void _irParaASenha() {
    if (!_formCodigo.currentState!.validate()) return;
    setState(() {
      _erroDoCodigo = null;
      _etapa = _Etapa.senha;
    });
  }

  Future<void> _redefinir() async {
    if (_enviando) return;
    if (!_formSenha.currentState!.validate()) return;

    final api = context.read<ApiService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _enviando = true);
    try {
      await api.auth.redefinirSenha(
        email: _email,
        codigo: _codigoCtrl.text.trim(),
        senhaNova: _novaCtrl.text,
      );
      TextInput.finishAutofillContext();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Senha redefinida. Entre com a senha nova.'),
          backgroundColor: AppColors.good,
        ),
      );
      _sair(navigator);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 400) {
        // O que sobra de 400 depois da validação da tela é o código: errado,
        // vencido ou esgotado. Volta ao passo dele, com a senha guardada.
        setState(() {
          _etapa = _Etapa.codigo;
          _erroDoCodigo = e.message;
        });
      } else {
        _avisar(e.message, erro: true);
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// A seta do cabeçalho e o voltar do sistema: um passo para trás, e só no
  /// primeiro passo sai da tela.
  void _voltar() {
    switch (_etapa) {
      case _Etapa.senha:
        setState(() => _etapa = _Etapa.codigo);
      case _Etapa.codigo:
        setState(() => _etapa = _Etapa.email);
      case _Etapa.email:
        _sair(Navigator.of(context));
    }
  }

  /// Volta ao login. Quem chegou por link direto não tem para onde dar `pop`
  /// — e um `pop` sem pilha deixa a tela em branco.
  void _sair(NavigatorState navigator) {
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(AppRoutes.login);
    }
  }

  void _avisar(String texto, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: erro ? AppColors.error : AppColors.tealDeep,
      ),
    );
  }

  // ── Tela ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _etapa == _Etapa.email,
      onPopInvokedWithResult: (saiu, _) {
        if (!saiu) _voltar();
      },
      child: AppScaffold(
        header: AppHeader.back(title: 'Recuperar senha', onBack: _voltar),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Passos(atual: _etapa.index + 1),
                    const SizedBox(height: 18),
                    switch (_etapa) {
                      _Etapa.email => _passoEmail(),
                      _Etapa.codigo => _passoCodigo(),
                      _Etapa.senha => _passoSenha(),
                    },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titulo(IconData icone, String titulo, String texto) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.tealSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icone, color: AppColors.tealDeep, size: 26),
        ),
        const SizedBox(height: 14),
        Text(titulo,
            style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        Text(texto,
            style: tsJakarta(12.5, FontWeight.w400,
                color: AppColors.mutedTexto, height: 1.5)),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _rotulo(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto.toUpperCase(),
            style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)),
      );

  InputDecoration _decoracao({String? dica, String? erro}) {
    OutlineInputBorder borda(Color cor) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: cor, width: 1.5),
        );
    return InputDecoration(
      filled: true,
      fillColor: AppColors.surface2,
      isDense: true,
      counterText: '',
      hintText: dica,
      errorText: erro,
      errorMaxLines: 2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: borda(AppColors.line),
      enabledBorder: borda(AppColors.line),
      focusedBorder: borda(AppColors.teal),
    );
  }

  // ── Passo 1: e-mail ──────────────────────────────────────────────────────

  Widget _passoEmail() {
    return Form(
      key: _formEmail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo(
            Icons.key_outlined,
            'Esqueceu a senha?',
            'Informe o e-mail da sua conta. Enviamos um código de 6 dígitos '
                'para você criar uma senha nova.',
          ),
          _rotulo('E-mail da conta'),
          TextFormField(
            key: const Key('recuperar-email'),
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            onFieldSubmitted: (_) => _pedirCodigo(),
            validator: Validators.email,
            style: tsJakarta(13, FontWeight.w500, color: AppColors.ink),
            decoration: _decoracao(dica: 'voce@email.com'),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            key: const Key('recuperar-enviar-codigo'),
            label: 'Enviar código',
            loading: _enviando,
            onPressed: _pedirCodigo,
          ),
          const SizedBox(height: 14),
          _nota(
            Icons.lock_open_outlined,
            'Redefinir a senha também desbloqueia a conta que ficou '
            'bloqueada por tentativas de login.',
          ),
          const SizedBox(height: 6),
          TextButton(
            key: const Key('recuperar-senha-voltar'),
            onPressed: () => _sair(Navigator.of(context)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.tealDeep,
              minimumSize: const Size(0, 44),
            ),
            child: Text('Voltar para o login',
                style:
                    tsJakarta(12.5, FontWeight.w700, color: AppColors.tealDeep)),
          ),
        ],
      ),
    );
  }

  // ── Passo 2: código ──────────────────────────────────────────────────────

  Widget _passoCodigo() {
    return Form(
      key: _formCodigo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo(
            Icons.mark_email_read_outlined,
            'Digite o código',
            'Se houver uma conta com o e-mail $_email, enviamos um código de '
                '6 dígitos para ele. O código vale por 15 minutos.',
          ),
          _rotulo('Código de 6 dígitos'),
          TextFormField(
            key: const Key('recuperar-codigo'),
            controller: _codigoCtrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            onChanged: (_) {
              if (_erroDoCodigo != null) setState(() => _erroDoCodigo = null);
            },
            onFieldSubmitted: (_) => _irParaASenha(),
            validator: (v) => (v ?? '').trim().length == 6
                ? null
                : 'O código tem 6 dígitos',
            style: tsJakarta(18, FontWeight.w700, color: AppColors.ink)
                .copyWith(letterSpacing: 6),
            decoration: _decoracao(dica: '000000', erro: _erroDoCodigo),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            key: const Key('recuperar-continuar'),
            label: 'Continuar',
            onPressed: _irParaASenha,
          ),
          const SizedBox(height: 14),
          _nota(
            Icons.info_outline_rounded,
            'Nesta versão o envio de e-mail é simulado: o código aparece no '
            'log do servidor, e não na sua caixa de entrada.',
            chave: const Key('recuperar-aviso-simulado'),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                key: const Key('recuperar-reenviar'),
                onPressed: _podeReenviar && !_enviando ? _pedirCodigo : null,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealDeep,
                  minimumSize: const Size(0, 44),
                ),
                child: Text(
                  _podeReenviar
                      ? 'Reenviar código'
                      : 'Reenviar código (aguarde 1 minuto)',
                  style: tsJakarta(12.5, FontWeight.w700),
                ),
              ),
              TextButton(
                key: const Key('recuperar-outro-email'),
                onPressed: () => setState(() => _etapa = _Etapa.email),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealDeep,
                  minimumSize: const Size(0, 44),
                ),
                child: Text('Usar outro e-mail',
                    style: tsJakarta(12.5, FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Passo 3: senha nova ──────────────────────────────────────────────────

  Widget _passoSenha() {
    return Form(
      key: _formSenha,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titulo(
              Icons.lock_reset_outlined,
              'Crie a senha nova',
              'Ela substitui a senha atual da conta $_email.',
            ),
            CampoDeSenha(
              key: const Key('recuperar-senha-nova'),
              rotulo: 'Senha nova',
              controller: _novaCtrl,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              validator: Validators.senha,
            ),
            CampoDeSenha(
              key: const Key('recuperar-senha-confirmar'),
              rotulo: 'Confirmar senha nova',
              controller: _confirmarCtrl,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _redefinir(),
              validator: (v) =>
                  v != _novaCtrl.text ? 'As senhas não conferem' : null,
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              key: const Key('recuperar-redefinir'),
              label: 'Redefinir senha',
              loading: _enviando,
              onPressed: _redefinir,
            ),
          ],
        ),
      ),
    );
  }

  Widget _nota(IconData icone, String texto, {Key? chave}) {
    return Container(
      key: chave,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 17, color: AppColors.tealDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto,
                style: tsJakarta(12, FontWeight.w500,
                    color: AppColors.text, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

/// "Passo 2 de 3", com as três barras.
class _Passos extends StatelessWidget {
  const _Passos({required this.atual});

  final int atual;

  static const int _total = 3;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Passo $atual de $_total',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PASSO $atual DE $_total',
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 1; i <= _total; i++) ...[
                if (i > 1) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= atual ? AppColors.teal : AppColors.surface3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
