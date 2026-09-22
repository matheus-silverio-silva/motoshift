import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';

/// O e-mail digitado no login, para a tela não pedir de novo o que a pessoa
/// acabou de escrever.
class RecuperarSenhaArgs {
  const RecuperarSenhaArgs({this.email});

  final String? email;
}

/// Rota `/esqueceu-senha`.
///
/// <h3>O que mudou e por quê</h3>
/// Esta tela era um stub com um capacete de obra e a palavra "Em breve". O
/// destino existia — o link do login levava a algum lugar —, mas quem chegava
/// aqui saía sem saber **o que fazer para voltar a entrar**, que é a única
/// pergunta de quem toca em "Esqueci minha senha".
///
/// A redefinição continua não sendo automática: não há endpoint de reset no
/// backend e o app não envia e-mail. O que a tela passa a fazer é dizer isso
/// e entregar o que ajuda de verdade:
///
/// * o e-mail que identifica a conta, pronto para copiar — o login do backend
///   procura a pessoa por `findByEmail`, então é esse o dado que a equipe
///   precisa para redefinir a senha;
/// * o aviso do bloqueio por tentativas. `AuthService.login` bloqueia a conta
///   por 15 minutos depois de 5 senhas erradas, e quem chega aqui costuma já
///   ter gastado algumas. Sem o aviso, a pessoa tenta mais uma vez e troca
///   "senha errada" por "conta bloqueada".
class RecuperarSenhaScreen extends StatelessWidget {
  const RecuperarSenhaScreen({super.key});

  /// Limite e janela do bloqueio — os mesmos de `AuthService.MAX_TENTATIVAS`
  /// e `AuthService.BLOQUEIO_MINUTOS` no backend.
  static const int _maxTentativas = 5;
  static const int _bloqueioMinutos = 15;

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final email = args is RecuperarSenhaArgs ? args.email?.trim() : null;
    final temEmail = email != null && email.isNotEmpty;

    return AppScaffold(
      header: AppHeader.back(title: 'Recuperar senha'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          _cabecalho(),
          const SizedBox(height: 18),
          if (temEmail) ...[
            _caixaDoEmail(context, email),
            const SizedBox(height: 12),
          ],
          _passos(temEmail),
          const SizedBox(height: 12),
          _avisoDeBloqueio(),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('recuperar-senha-voltar'),
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.teal,
              minimumSize: const Size(0, 48),
            ),
            child: Text('Voltar para o login',
                style: tsJakarta(13, FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho() {
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
          child: const Icon(Icons.key_outlined,
              color: AppColors.tealDeep, size: 26),
        ),
        const SizedBox(height: 14),
        Text('A redefinição ainda não é automática',
            style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        Text(
          'Esta versão do MotoShift não envia e-mail de redefinição. Quem '
          'troca a senha é a equipe responsável pelo aplicativo, e para isso '
          'ela precisa do e-mail da sua conta.',
          style: tsJakarta(12.5, FontWeight.w400,
              color: AppColors.muted, height: 1.5),
        ),
      ],
    );
  }

  /// O e-mail digitado no login, com um botão para copiar.
  Widget _caixaDoEmail(BuildContext context, String email) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.alternate_email_rounded,
              size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('E-mail da conta',
                    style: tsJakarta(11, FontWeight.w500,
                        color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(13, FontWeight.w700,
                        color: AppColors.text)),
              ],
            ),
          ),
          TextButton(
            key: const Key('recuperar-senha-copiar'),
            onPressed: () => _copiar(context, email),
            child: Text('Copiar',
                style: tsJakarta(12, FontWeight.w700, color: AppColors.teal)),
          ),
        ],
      ),
    );
  }

  Future<void> _copiar(BuildContext context, String email) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: email));
    messenger.showSnackBar(
      SnackBar(
        content: Text('E-mail copiado.',
            style: tsJakarta(12.5, FontWeight.w600, color: Colors.white)),
        backgroundColor: AppColors.tealDeep,
      ),
    );
  }

  Widget _passos(bool temEmail) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Como voltar a entrar',
              style: tsJakarta(13, FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 12),
          _passo(
            1,
            temEmail
                ? 'Peça a redefinição à equipe do MotoShift informando o '
                    'e-mail acima.'
                : 'Peça a redefinição à equipe do MotoShift informando o '
                    'e-mail com que você se cadastrou.',
          ),
          _passo(
            2,
            'Você recebe uma senha provisória e entra com ela na tela de '
            'login.',
          ),
          _passo(
            3,
            temEmail
                ? 'Se o e-mail acima não for o da sua conta, volte e tente com '
                    'o endereço certo — é por ele que o login encontra você.'
                : 'O login encontra a conta pelo e-mail: confira se está '
                    'digitando o mesmo endereço do cadastro.',
            ultimo: true,
          ),
        ],
      ),
    );
  }

  Widget _passo(int numero, String texto, {bool ultimo = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: ultimo ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(
              child: Text('$numero',
                  style: tsJakarta(11, FontWeight.w800,
                      color: AppColors.tealDeep)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto,
                style: tsJakarta(12.5, FontWeight.w400,
                    color: AppColors.text, height: 1.45)),
          ),
        ],
      ),
    );
  }

  /// O aviso que evita trocar um problema por outro pior.
  Widget _avisoDeBloqueio() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_clock_outlined,
              size: 19, color: AppColors.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cuidado com o chute: depois de $_maxTentativas senhas erradas '
              'a conta fica bloqueada por $_bloqueioMinutos minutos.',
              style: tsJakarta(12, FontWeight.w500,
                  color: AppColors.onTertiaryContainer, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
