/// Validadores reutilizáveis para formulários da aplicação.
///
/// Centraliza as regras de validação para evitar duplicação e garantir que
/// "informação inválida ou repetida" seja barrada de forma consistente em
/// todas as telas (cadastro, perfil, dados pessoais, CNH/veículo, etc.).
///
/// Todos os métodos seguem a assinatura de `FormFieldValidator<String>`:
/// retornam `null` quando válido, ou a mensagem de erro quando inválido.
class Validators {
  Validators._();

  // ── Genéricos ──────────────────────────────────────────────────────────

  static String? obrigatorio(String? v, {String campo = 'Campo'}) {
    if (v == null || v.trim().isEmpty) return '$campo obrigatório';
    return null;
  }

  static String? nome(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Informe seu nome';
    if (t.length < 3) return 'Nome muito curto';
    if (!t.contains(' ')) return 'Informe nome e sobrenome';
    if (!RegExp(r"^[A-Za-zÀ-ÿ' ]+$").hasMatch(t)) {
      return 'Nome não pode conter números ou símbolos';
    }
    return null;
  }

  // ── E-mail ─────────────────────────────────────────────────────────────

  static final RegExp _emailRe =
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

  static String? email(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Informe o e-mail';
    if (!_emailRe.hasMatch(t)) return 'E-mail inválido';
    return null;
  }

  // ── Telefone (BR: 10 ou 11 dígitos com DDD) ────────────────────────────

  static String? telefone(String? v) {
    final d = _digitos(v);
    if (d.isEmpty) return 'Informe o telefone';
    if (d.length < 10 || d.length > 11) {
      return 'Telefone inválido — use DDD + número';
    }
    // DDD válido (11–99) e, para celular, 9 na terceira posição.
    final ddd = int.tryParse(d.substring(0, 2)) ?? 0;
    if (ddd < 11) return 'DDD inválido';
    if (d.length == 11 && d[2] != '9') return 'Celular deve começar com 9';
    return null;
  }

  // ── Senha ──────────────────────────────────────────────────────────────

  static String? senha(String? v) {
    final t = v ?? '';
    if (t.isEmpty) return 'Informe uma senha';
    if (t.length < 6) return 'Mínimo 6 caracteres';
    if (!RegExp(r'[A-Za-z]').hasMatch(t) || !RegExp(r'[0-9]').hasMatch(t)) {
      return 'Use letras e números';
    }
    return null;
  }

  static String? confirmarSenha(String? v, String original) {
    if (v == null || v.isEmpty) return 'Confirme a senha';
    if (v != original) return 'As senhas não coincidem';
    return null;
  }

  // ── Documento federal ──────────────────────────────────────────────────

  /// Valida CNPJ (lojista) ou CNH (motoboy) conforme o tipo.
  static String? documento(String? v, {required bool isLojista}) {
    return isLojista ? cnpj(v) : cnh(v);
  }

  /// CNPJ com dígitos verificadores (algoritmo oficial da Receita).
  static String? cnpj(String? v) {
    final d = _digitos(v);
    if (d.isEmpty) return 'Informe o CNPJ';
    if (d.length != 14) return 'CNPJ deve ter 14 dígitos';
    if (RegExp(r'^(\d)\1{13}$').hasMatch(d)) return 'CNPJ inválido';

    int calc(int len) {
      const pesos = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
      final offset = 13 - len;
      var soma = 0;
      for (var i = 0; i < len; i++) {
        soma += int.parse(d[i]) * pesos[offset + i];
      }
      final r = soma % 11;
      return r < 2 ? 0 : 11 - r;
    }

    if (calc(12) != int.parse(d[12]) || calc(13) != int.parse(d[13])) {
      return 'CNPJ inválido';
    }
    return null;
  }

  /// CNH com dígito verificador (algoritmo do Denatran).
  static String? cnh(String? v) {
    final d = _digitos(v);
    if (d.isEmpty) return 'Informe a CNH';
    if (d.length != 11) return 'CNH deve ter 11 dígitos';
    if (RegExp(r'^(\d)\1{10}$').hasMatch(d)) return 'CNH inválida';

    var soma1 = 0, soma2 = 0;
    for (var i = 0, j = 9; i < 9; i++, j--) {
      final n = int.parse(d[i]);
      soma1 += n * j;
      soma2 += n * (i + 1);
    }
    var dsc = 0;
    var v1 = soma1 % 11;
    if (v1 >= 10) {
      v1 = 0;
      dsc = 2;
    }
    var v2 = (soma2 % 11) - dsc;
    if (v2 < 0) v2 += 11;
    if (v2 >= 10) v2 = 0;

    if (v1 != int.parse(d[9]) || v2 != int.parse(d[10])) {
      return 'CNH inválida';
    }
    return null;
  }

  /// CPF com dígitos verificadores (para dados pessoais, se necessário).
  static String? cpf(String? v) {
    final d = _digitos(v);
    if (d.isEmpty) return 'Informe o CPF';
    if (d.length != 11) return 'CPF deve ter 11 dígitos';
    if (RegExp(r'^(\d)\1{10}$').hasMatch(d)) return 'CPF inválido';

    int calc(int len) {
      var soma = 0;
      for (var i = 0; i < len; i++) {
        soma += int.parse(d[i]) * ((len + 1) - i);
      }
      final r = (soma * 10) % 11;
      return r == 10 ? 0 : r;
    }

    if (calc(9) != int.parse(d[9]) || calc(10) != int.parse(d[10])) {
      return 'CPF inválido';
    }
    return null;
  }

  // ── Placa de veículo (Mercosul + antiga) ───────────────────────────────

  static String? placa(String? v) {
    final t = (v ?? '').trim().toUpperCase().replaceAll('-', '');
    if (t.isEmpty) return 'Informe a placa';
    final antiga = RegExp(r'^[A-Z]{3}[0-9]{4}$');
    final mercosul = RegExp(r'^[A-Z]{3}[0-9][A-Z][0-9]{2}$');
    if (!antiga.hasMatch(t) && !mercosul.hasMatch(t)) {
      return 'Placa inválida';
    }
    return null;
  }

  static String _digitos(String? v) => (v ?? '').replaceAll(RegExp(r'\D'), '');
}
