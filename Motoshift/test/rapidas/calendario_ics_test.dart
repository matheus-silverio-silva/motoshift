import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/utils/calendario_ics.dart';

/// O `.ics` do turno (RFC 5545): fuso de Curitiba, alarme de 1 h, texto
/// escapado e linhas de até 75 octetos.
void main() {
  final turno = Turno(
    id: 77,
    lojistId: 2,
    titulo: 'Turno Noite — Hamburgueria da Cláudia',
    descricao: 'Entregas noturnas; bairro Água Verde, Batel',
    regiao: 'Água Verde, Curitiba',
    endereco: 'Av. Água Verde, 1200 — Água Verde, Curitiba/PR',
    dataInicio: DateTime(2026, 10, 2, 18),
    dataFim: DateTime(2026, 10, 2, 22),
    valorEstimado: 130,
    raioEntregaKm: 8,
    latitude: -25.456,
    longitude: -49.282,
    status: StatusTurno.aceito,
  );
  final agora = DateTime.utc(2026, 9, 28, 13, 5, 9);
  final ics = CalendarioIcs.gerar(turno, agora: agora);
  final linhas = ics.split('\r\n');

  /// Desdobra as linhas (3.1): CRLF seguido de espaço é continuação.
  String desdobrado() => ics.replaceAll('\r\n ', '');

  test('linhas separadas por CRLF, do VCALENDAR ao fim', () {
    expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect(ics.replaceAll('\r\n', ''), isNot(contains('\n')));
  });

  test('horário de parede de Curitiba, com o VTIMEZONE junto', () {
    final t = desdobrado();
    expect(t, contains('BEGIN:VTIMEZONE\r\nTZID:America/Sao_Paulo'));
    expect(t, contains('TZOFFSETTO:-0300'));
    expect(t, contains('DTSTART;TZID=America/Sao_Paulo:20261002T180000'));
    expect(t, contains('DTEND;TZID=America/Sao_Paulo:20261002T220000'));
    expect(t, contains('DTSTAMP:20260928T130509Z'));
    expect(t, contains('UID:turno-77@motoshift'));
  });

  test('alarme de uma hora antes', () {
    final t = desdobrado();
    expect(t, contains('BEGIN:VALARM\r\nACTION:DISPLAY'));
    expect(t, contains('TRIGGER:-PT1H'));
  });

  test('título, endereço e descrição com vírgula e ponto e vírgula escapados', () {
    final t = desdobrado();
    expect(t, contains('SUMMARY:Turno Noite — Hamburgueria da Cláudia'));
    expect(t, contains('LOCATION:Av. Água Verde\\, 1200 — Água Verde\\, Curitiba/PR'));
    expect(t, contains('DESCRIPTION:Turno MotoShift — R\$ 130\\,00\\, raio de 8 km.\\n'
        'Entregas noturnas\\; bairro Água Verde\\, Batel'));
    expect(t, contains('GEO:-25.456000;-49.282000'));
  });

  test('nenhuma linha passa de 75 octetos, e a dobra não parte um caractere', () {
    for (final l in linhas) {
      expect(utf8.encode(l).length, lessThanOrEqualTo(75), reason: l);
    }
    // Uma linha longa de verdade, cheia de acentos, dobra e volta igual.
    final longa = 'DESCRIPTION:${'Ação à distância — ' * 8}';
    final dobrada = CalendarioIcs.dobrar(longa);
    expect(dobrada, contains('\r\n '));
    expect(dobrada.replaceAll('\r\n ', ''), longa);
    for (final parte in dobrada.split('\r\n')) {
      expect(utf8.encode(parte).length, lessThanOrEqualTo(75));
    }
  });

  test('nome do arquivo com o id e a data', () {
    expect(CalendarioIcs.nomeDoArquivo(turno), 'turno-77-20261002.ics');
  });
}
