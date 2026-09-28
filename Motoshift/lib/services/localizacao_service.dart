import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'plataforma/contexto_seguro.dart';

/// Por que não há posição — cada motivo pede uma mensagem diferente na tela.
enum FalhaLocalizacao {
  /// O usuário negou a permissão nesta sessão; dá para pedir de novo.
  permissaoNegada,

  /// Negada permanentemente: só resolve nas configurações do sistema.
  permissaoNegadaParaSempre,

  /// GPS/localização desligado no aparelho.
  servicoDesligado,

  /// O aparelho (ou o navegador) não respondeu dentro do tempo limite.
  tempoEsgotado,

  /// Página web aberta fora de HTTPS/localhost: o navegador nem pergunta.
  contextoInseguro,

  /// Erro inesperado ao consultar a posição.
  erro,
}

/// O que dizer, e o que oferecer, para cada motivo — num lugar só, para a
/// lista de turnos, a publicação e o check-in falarem a mesma língua.
extension MensagemDaFalha on FalhaLocalizacao {
  String get mensagem => switch (this) {
        FalhaLocalizacao.permissaoNegada =>
          'Sem permissão de localização. Você pode permitir e tentar de novo.',
        FalhaLocalizacao.permissaoNegadaParaSempre =>
          'A permissão de localização está bloqueada para o app. Libere nas '
              'configurações do sistema.',
        FalhaLocalizacao.servicoDesligado =>
          'A localização do aparelho está desligada. Ligue o GPS e tente de novo.',
        FalhaLocalizacao.tempoEsgotado =>
          'O aparelho não respondeu com a sua posição. Se o navegador mostrou '
              'um pedido de permissão, aceite-o e tente de novo.',
        FalhaLocalizacao.contextoInseguro =>
          'O navegador só libera a localização em páginas HTTPS ou em '
              'localhost. Abra o app pelo endereço https:// (ou por '
              'localhost no computador) para usar a distância.',
        FalhaLocalizacao.erro => 'Não foi possível obter sua localização agora.',
      };

  /// Tentar de novo resolve? Negada para sempre e página insegura, não: o
  /// que resolve está fora do app.
  bool get podeTentarDeNovo =>
      this != FalhaLocalizacao.permissaoNegadaParaSempre &&
      this != FalhaLocalizacao.contextoInseguro;
}

/// Resultado da tentativa de obter a posição: ou veio a coordenada, ou veio o
/// motivo de não ter vindo. Nunca "silenciosamente vazio" — a tela 18 precisa
/// distinguir "sem turnos por perto" de "não sei onde você está".
class ResultadoLocalizacao {
  const ResultadoLocalizacao.sucesso(this.latitude, this.longitude)
      : falha = null;
  const ResultadoLocalizacao.falhou(this.falha)
      : latitude = null,
        longitude = null;

  final double? latitude;
  final double? longitude;
  final FalhaLocalizacao? falha;

  bool get temPosicao => latitude != null && longitude != null;
}

/// As chamadas ao `geolocator` que o serviço faz, num lugar que o teste troca.
class FonteDePosicao {
  const FonteDePosicao();

  Future<bool> servicoLigado() => Geolocator.isLocationServiceEnabled();
  Future<LocationPermission> permissao() => Geolocator.checkPermission();
  Future<LocationPermission> pedirPermissao() => Geolocator.requestPermission();
  Future<Position> posicao(LocationSettings ajustes) =>
      Geolocator.getCurrentPosition(locationSettings: ajustes);
  Future<Position?> ultimaConhecida() => Geolocator.getLastKnownPosition();
  Future<void> abrirConfiguracoes() => Geolocator.openAppSettings();

  bool get ehWeb => kIsWeb;
  bool get contextoSeguro => contextoSeguroDoNavegador();
}

/// Acesso à localização do dispositivo.
class LocalizacaoService {
  const LocalizacaoService({
    this.fonte = const FonteDePosicao(),
    this.limite = const Duration(seconds: 15),
    this.idadeMaximaDaUltima = const Duration(minutes: 2),
  });

  final FonteDePosicao fonte;
  final Duration limite;
  final Duration idadeMaximaDaUltima;

  /// O serviço da árvore, quando houver um (os testes põem um fake); senão o
  /// do aparelho.
  static LocalizacaoService of(BuildContext context) {
    try {
      return Provider.of<LocalizacaoService>(context, listen: false);
    } on ProviderNotFoundException {
      return const LocalizacaoService();
    }
  }

  /// A posição do aparelho, ou o motivo de não haver uma — sempre dentro de
  /// [limite].
  ///
  /// O limite vale para a consulta inteira, e não só para o GPS: no web, um
  /// pedido de permissão que ninguém responde prende o `requestPermission`
  /// para sempre, antes mesmo de o GPS ser consultado. Era o "buscando
  /// localização" que não terminava.
  Future<ResultadoLocalizacao> posicaoAtual() async {
    // O navegador nega a geolocalização fora de HTTPS/localhost sem nem
    // perguntar — e sem dizer o porquê. Aqui o porquê é dito.
    if (fonte.ehWeb && !fonte.contextoSeguro) {
      return const ResultadoLocalizacao.falhou(
          FalhaLocalizacao.contextoInseguro);
    }
    try {
      return await _consultar().timeout(
        limite,
        onTimeout: () => const ResultadoLocalizacao.falhou(
            FalhaLocalizacao.tempoEsgotado),
      );
    } catch (_) {
      return const ResultadoLocalizacao.falhou(FalhaLocalizacao.erro);
    }
  }

  Future<ResultadoLocalizacao> _consultar() async {
    if (!await fonte.servicoLigado()) {
      return const ResultadoLocalizacao.falhou(
          FalhaLocalizacao.servicoDesligado);
    }

    var permissao = await fonte.permissao();
    if (permissao == LocationPermission.denied) {
      permissao = await fonte.pedirPermissao();
    }

    if (permissao == LocationPermission.deniedForever) {
      return const ResultadoLocalizacao.falhou(
          FalhaLocalizacao.permissaoNegadaParaSempre);
    }
    if (permissao == LocationPermission.denied) {
      return const ResultadoLocalizacao.falhou(
          FalhaLocalizacao.permissaoNegada);
    }

    // No celular, a última posição conhecida chega na hora; se for recente,
    // poupa a espera do GPS. No web ela não existe.
    if (!fonte.ehWeb) {
      final ultima = await fonte.ultimaConhecida();
      if (ultima != null &&
          clock.now().difference(ultima.timestamp) <= idadeMaximaDaUltima) {
        return ResultadoLocalizacao.sucesso(ultima.latitude, ultima.longitude);
      }
    }

    final pos = await fonte.posicao(LocationSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: limite,
    ));
    return ResultadoLocalizacao.sucesso(pos.latitude, pos.longitude);
  }

  Future<void> abrirConfiguracoes() => fonte.abrirConfiguracoes();
}
