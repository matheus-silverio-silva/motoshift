import 'package:geolocator/geolocator.dart';

/// Por que não há posição — cada motivo pede uma mensagem diferente na tela.
enum FalhaLocalizacao {
  /// O usuário negou a permissão nesta sessão; dá para pedir de novo.
  permissaoNegada,

  /// Negada permanentemente: só resolve nas configurações do sistema.
  permissaoNegadaParaSempre,

  /// GPS/localização desligado no aparelho.
  servicoDesligado,

  /// Erro inesperado ao consultar a posição.
  erro,
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

/// Acesso à localização do dispositivo.
class LocalizacaoService {
  const LocalizacaoService();

  Future<ResultadoLocalizacao> posicaoAtual() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const ResultadoLocalizacao.falhou(
            FalhaLocalizacao.servicoDesligado);
      }

      var permissao = await Geolocator.checkPermission();
      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }

      if (permissao == LocationPermission.deniedForever) {
        return const ResultadoLocalizacao.falhou(
            FalhaLocalizacao.permissaoNegadaParaSempre);
      }
      if (permissao == LocationPermission.denied) {
        return const ResultadoLocalizacao.falhou(
            FalhaLocalizacao.permissaoNegada);
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      return ResultadoLocalizacao.sucesso(pos.latitude, pos.longitude);
    } catch (_) {
      return const ResultadoLocalizacao.falhou(FalhaLocalizacao.erro);
    }
  }

  Future<void> abrirConfiguracoes() => Geolocator.openAppSettings();
}
