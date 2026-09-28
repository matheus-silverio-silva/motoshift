import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:moto_shift/services/localizacao_service.dart';

import 'fonte_falsa.dart';

/// O serviço de localização nunca deixa a tela esperando para sempre, e diz
/// por que não há posição.
///
/// Suspeitas da auditoria de localização que moram aqui:
/// - **5** — `getCurrentPosition` sem tempo limite: no web, um aviso de
///   permissão ignorado deixava "buscando localização" para sempre;
/// - **6** — web fora de HTTPS: o navegador nega a geolocalização sem nem
///   perguntar, e o app dizia só "não foi possível".
void main() {
  group('tempo limite (suspeita 5)', () {
    testWidgets('aviso de permissão ignorado no navegador termina em tempo esgotado',
        (tester) async {
      final fonte = FonteFalsa(permissaoAtual: LocationPermission.denied)
        ..permissaoPendente = Completer<LocationPermission>();
      final servico = LocalizacaoService(fonte: fonte);

      ResultadoLocalizacao? resultado;
      unawaited(servico.posicaoAtual().then((r) => resultado = r));

      await tester.pump(const Duration(seconds: 14));
      expect(resultado, isNull, reason: 'antes do limite, ainda esperando');

      await tester.pump(const Duration(seconds: 2));
      expect(resultado, isNotNull, reason: 'passou do limite e não respondeu');
      expect(resultado!.temPosicao, isFalse);
      expect(resultado!.falha, FalhaLocalizacao.tempoEsgotado);
    });

    testWidgets('GPS que não devolve posição também para no limite', (tester) async {
      final fonte = FonteFalsa()..posicaoPendente = Completer<Position>();
      final servico = LocalizacaoService(fonte: fonte);

      ResultadoLocalizacao? resultado;
      unawaited(servico.posicaoAtual().then((r) => resultado = r));
      await tester.pump(const Duration(seconds: 16));

      expect(resultado?.falha, FalhaLocalizacao.tempoEsgotado);
    });

    test('a mensagem do tempo esgotado diz o que fazer', () {
      final msg = FalhaLocalizacao.tempoEsgotado.mensagem;
      expect(msg, contains('não respondeu'));
      expect(msg, contains('permissão'));
      expect(FalhaLocalizacao.tempoEsgotado.podeTentarDeNovo, isTrue);
    });
  });

  group('última posição conhecida (mobile)', () {
    test('recente, é usada sem esperar o GPS', () async {
      final fonte = FonteFalsa(ultima: posicaoEm(-25.1, -49.1));
      final r = await LocalizacaoService(fonte: fonte).posicaoAtual();

      expect(r.latitude, -25.1);
      expect(fonte.chamadasDePosicao, 0);
    });

    test('velha, é ignorada: o GPS é consultado', () async {
      final fonte = FonteFalsa(
        ultima: posicaoEm(-25.1, -49.1,
            quando: DateTime.now().subtract(const Duration(hours: 1))),
      );
      final r = await LocalizacaoService(fonte: fonte).posicaoAtual();

      expect(r.latitude, -25.4560);
      expect(fonte.chamadasDePosicao, 1);
    });

    test('no web não existe: vai direto ao GPS', () async {
      final fonte = FonteFalsa(web: true, ultima: posicaoEm(-25.1, -49.1));
      final r = await LocalizacaoService(fonte: fonte).posicaoAtual();

      expect(r.latitude, -25.4560);
      expect(fonte.chamadasDePosicao, 1);
    });
  });

  group('web fora de HTTPS (suspeita 6)', () {
    test('página insegura não pede posição e diz o porquê', () async {
      final fonte = FonteFalsa(web: true, seguro: false);
      final r = await LocalizacaoService(fonte: fonte).posicaoAtual();

      expect(r.falha, FalhaLocalizacao.contextoInseguro);
      expect(fonte.consultasAoServico, 0, reason: 'nem chega a perguntar');
      expect(FalhaLocalizacao.contextoInseguro.mensagem, contains('HTTPS'));
      expect(FalhaLocalizacao.contextoInseguro.mensagem, contains('localhost'));
      expect(FalhaLocalizacao.contextoInseguro.podeTentarDeNovo, isFalse);
    });

    test('https ou localhost seguem normalmente', () async {
      final r = await LocalizacaoService(fonte: FonteFalsa(web: true, seguro: true))
          .posicaoAtual();
      expect(r.temPosicao, isTrue);
    });
  });

  group('os outros motivos continuam distintos', () {
    test('GPS desligado, permissão negada, negada para sempre, erro', () async {
      expect(
          (await LocalizacaoService(fonte: FonteFalsa(ligado: false)).posicaoAtual())
              .falha,
          FalhaLocalizacao.servicoDesligado);
      expect(
          (await LocalizacaoService(
                      fonte: FonteFalsa(permissaoAtual: LocationPermission.denied))
                  .posicaoAtual())
              .falha,
          FalhaLocalizacao.permissaoNegada);
      expect(
          (await LocalizacaoService(
                      fonte: FonteFalsa(
                          permissaoAtual: LocationPermission.deniedForever))
                  .posicaoAtual())
              .falha,
          FalhaLocalizacao.permissaoNegadaParaSempre);
      expect(
          (await LocalizacaoService(fonte: FonteFalsa(falhar: true)).posicaoAtual())
              .falha,
          FalhaLocalizacao.erro);
    });

    test('toda falha tem mensagem própria', () {
      final mensagens = FalhaLocalizacao.values.map((f) => f.mensagem).toSet();
      expect(mensagens, hasLength(FalhaLocalizacao.values.length));
    });
  });
}
