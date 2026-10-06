import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/campo_de_senha.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';

/// Rota `/alterar-senha`, aberta a partir do Perfil (SCRUM-32).
///
/// Quem está logado troca a senha informando a atual. A prova de que é o dono
/// da conta é dupla — o token da sessão e a senha que já conhece —, e por
/// isso não há código por e-mail aqui: esse é o caminho de quem NÃO lembra a
/// senha, na tela de recuperação.
///
/// A senha atual errada vem do backend como 400, e aparece no próprio campo.
/// Não derruba a sessão nem conta como tentativa de login.
class AlterarSenhaScreen extends StatefulWidget {
  const AlterarSenhaScreen({super.key});

  @override
  State<AlterarSenhaScreen> createState() => _AlterarSenhaScreenState();
}

class _AlterarSenhaScreenState extends State<AlterarSenhaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _atualCtrl = TextEditingController();
  final _novaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();

  bool _salvando = false;

  /// O que o servidor disse da senha atual. Some quando a pessoa volta a
  /// digitar no campo: o erro era do valor antigo.
  String? _erroDaAtual;

  @override
  void dispose() {
    _atualCtrl.dispose();
    _novaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() => _erroDaAtual = null);
    if (!_formKey.currentState!.validate()) return;

    final api = context.read<ApiService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _salvando = true);
    try {
      await api.auth.trocarSenha(
        senhaAtual: _atualCtrl.text,
        senhaNova: _novaCtrl.text,
      );
      // Diz ao gerenciador de senhas que o formulário terminou bem: é o que
      // faz ele oferecer atualizar a senha guardada.
      TextInput.finishAutofillContext();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Senha alterada.'),
          backgroundColor: AppColors.good,
        ),
      );
      if (navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 400) {
        // O único 400 que passa pela validação da tela é a senha atual.
        setState(() => _erroDaAtual = e.message);
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Alterar senha'),
      desktopTitle: 'Alterar senha',
      desktopSubtitle: 'Informe a senha atual e escolha a nova',
      desktopBody: ContentGrid(
        children: [
          GridCol(
            span: 6,
            child: PanelCard(
              title: 'Senha de acesso',
              child: _formulario(),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        child: _formulario(),
      ),
    );
  }

  Widget _formulario() {
    return Form(
      key: _formKey,
      // AutofillGroup: o gerenciador de senhas enxerga "senha atual" e "senha
      // nova" como um formulário só, e sabe qual das duas guardar.
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A senha nova passa a valer no próximo login. Você continua '
              'conectado neste aparelho.',
              style: tsJakarta(12.5, FontWeight.w400,
                  color: AppColors.mutedTexto, height: 1.5),
            ),
            const SizedBox(height: 18),
            CampoDeSenha(
              key: const Key('alterar-senha-atual'),
              rotulo: 'Senha atual',
              controller: _atualCtrl,
              erro: _erroDaAtual,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_erroDaAtual != null) setState(() => _erroDaAtual = null);
              },
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Informe a senha atual' : null,
            ),
            CampoDeSenha(
              key: const Key('alterar-senha-nova'),
              rotulo: 'Senha nova',
              controller: _novaCtrl,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              validator: (v) {
                final erro = Validators.senha(v);
                if (erro != null) return erro;
                if (v == _atualCtrl.text) {
                  return 'A senha nova precisa ser diferente da atual';
                }
                return null;
              },
            ),
            CampoDeSenha(
              key: const Key('alterar-senha-confirmar'),
              rotulo: 'Confirmar senha nova',
              controller: _confirmarCtrl,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _salvar(),
              validator: (v) =>
                  v != _novaCtrl.text ? 'As senhas não conferem' : null,
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              key: const Key('alterar-senha-salvar'),
              label: 'Alterar senha',
              loading: _salvando,
              onPressed: _salvar,
            ),
          ],
        ),
      ),
    );
  }
}
