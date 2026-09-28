import 'usuario.dart';

/// Os "pontos positivos" que se marca ao avaliar — uma lista por papel de
/// quem é avaliado.
///
/// Era uma lista só para os dois lados, e o lojista avaliava o entregador por
/// "Carga bem embalada" e "Pagamento correto", que é o que a loja faz, não o
/// entregador; e o entregador avaliava a loja por "Pontual". Cada lado agora
/// escolhe entre o que o outro de fato faz.
///
/// "Pagamento correto" saiu também da lista da loja: com a liquidação
/// automática, o dinheiro é reservado na publicação e transferido na
/// finalização — a loja não tem como pagar errado. No lugar ficou "Valor
/// justo", que é o que o entregador realmente avalia no pagamento.
class TagsDeAvaliacao {
  TagsDeAvaliacao._();

  /// O lojista avaliando o entregador.
  static const doEntregador = [
    'Pontual',
    'Cuidado com a carga',
    'Educado',
    'Conhece a região',
    'Boa comunicação',
  ];

  /// O entregador avaliando a loja.
  static const daLoja = [
    'Pedidos prontos no horário',
    'Carga bem embalada',
    'Endereços corretos',
    'Boa comunicação',
    'Valor justo',
  ];

  /// As tags para avaliar alguém de [papelDoAvaliado].
  static List<String> para(TipoUsuario papelDoAvaliado) =>
      papelDoAvaliado == TipoUsuario.motoboy ? doEntregador : daLoja;
}
