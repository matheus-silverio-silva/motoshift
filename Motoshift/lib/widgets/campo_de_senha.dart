import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'olho_da_senha.dart';

/// Campo de senha com rótulo em cima e o olho de mostrar/ocultar.
///
/// É o campo das telas "Alterar senha" e "Recuperar senha" — três senhas numa
/// e duas na outra, todas com o mesmo desenho dos campos de "Dados pessoais".
/// O estado do olho mora aqui: quem usa só entrega o controller.
class CampoDeSenha extends StatefulWidget {
  const CampoDeSenha({
    required this.rotulo,
    required this.controller,
    this.validator,
    this.erro,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    super.key,
  });

  final String rotulo;
  final TextEditingController controller;
  final String? Function(String?)? validator;

  /// Erro que veio do servidor para este campo ("A senha atual não confere.").
  /// Tem o mesmo desenho do erro de validação, porque para quem lê é a mesma
  /// coisa: este campo está errado.
  final String? erro;

  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<CampoDeSenha> createState() => _CampoDeSenhaState();
}

class _CampoDeSenhaState extends State<CampoDeSenha> {
  bool _visivel = false;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder borda(Color cor) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: cor, width: 1.5),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.rotulo.toUpperCase(),
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 8),
          TextFormField(
            controller: widget.controller,
            obscureText: !_visivel,
            validator: widget.validator,
            autofillHints: widget.autofillHints,
            textInputAction: widget.textInputAction,
            onFieldSubmitted: widget.onSubmitted,
            onChanged: widget.onChanged,
            // Senha não se corrige nem se sugere.
            autocorrect: false,
            enableSuggestions: false,
            style: tsJakarta(13, FontWeight.w500, color: AppColors.ink),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface2,
              isDense: true,
              errorText: widget.erro,
              errorMaxLines: 2,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: borda(AppColors.line),
              enabledBorder: borda(AppColors.line),
              focusedBorder: borda(AppColors.teal),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: OlhoDaSenha(
                  visivel: _visivel,
                  onTap: () => setState(() => _visivel = !_visivel),
                ),
              ),
              suffixIconConstraints:
                  const BoxConstraints(maxWidth: 44, maxHeight: 32),
            ),
          ),
        ],
      ),
    );
  }
}
