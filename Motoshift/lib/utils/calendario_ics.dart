import 'dart:convert';

import '../models/turno.dart';

/// O turno como evento de calendário — um arquivo `.ics` (RFC 5545) que o
/// Google Agenda, o Outlook e o Calendário do iPhone abrem.
///
/// <h3>Fuso</h3>
/// O backend guarda e devolve o horário de parede de Curitiba, sem fuso
/// ("2026-10-02T18:00:00"). O evento diz isso com todas as letras:
/// `DTSTART;TZID=America/Sao_Paulo:20261002T180000`, com o VTIMEZONE junto.
/// Sem o TZID, "18:00" viraria 18:00 do fuso de quem abre o arquivo — ou 18:00
/// UTC, três horas antes.
///
/// <h3>Alarme</h3>
/// Um VALARM de uma hora antes, o mesmo prazo do lembrete que o backend manda.
class CalendarioIcs {
  CalendarioIcs._();

  static const fuso = 'America/Sao_Paulo';

  static String nomeDoArquivo(Turno t) {
    final d = t.dataInicio;
    return 'turno-${t.id ?? 'novo'}-${d.year}${_doisDigitos(d.month)}${_doisDigitos(d.day)}.ics';
  }

  static List<int> bytes(Turno t, {required DateTime agora}) =>
      utf8.encode(gerar(t, agora: agora));

  /// O arquivo inteiro, com CRLF entre as linhas e as longas dobradas.
  static String gerar(Turno t, {required DateTime agora}) {
    final local = (t.endereco?.trim().isNotEmpty ?? false)
        ? t.endereco!.trim()
        : t.regiao;
    final valor = 'R\$ ${t.valorEstimado.toStringAsFixed(2).replaceAll('.', ',')}';
    final descricao = [
      'Turno MotoShift — $valor, raio de ${t.raioEntregaKm.toStringAsFixed(0)} km.',
      if (t.descricao?.trim().isNotEmpty ?? false) t.descricao!.trim(),
    ].join('\n');

    final linhas = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//MotoShift//Turnos//PT-BR',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'BEGIN:VTIMEZONE',
      'TZID:$fuso',
      'X-LIC-LOCATION:$fuso',
      // Sem horário de verão desde 2019: um STANDARD só, -03:00 o ano todo.
      'BEGIN:STANDARD',
      'TZOFFSETFROM:-0300',
      'TZOFFSETTO:-0300',
      'TZNAME:-03',
      'DTSTART:19700101T000000',
      'END:STANDARD',
      'END:VTIMEZONE',
      'BEGIN:VEVENT',
      'UID:turno-${t.id ?? t.dataInicio.millisecondsSinceEpoch}@motoshift',
      'DTSTAMP:${_utc(agora)}',
      'DTSTART;TZID=$fuso:${_local(t.dataInicio)}',
      'DTEND;TZID=$fuso:${_local(t.dataFim)}',
      'SUMMARY:${escapar(t.titulo)}',
      'LOCATION:${escapar(local)}',
      'DESCRIPTION:${escapar(descricao)}',
      if (t.latitude != null && t.longitude != null)
        'GEO:${t.latitude!.toStringAsFixed(6)};${t.longitude!.toStringAsFixed(6)}',
      'STATUS:CONFIRMED',
      'BEGIN:VALARM',
      'ACTION:DISPLAY',
      'DESCRIPTION:${escapar('Seu turno começa em 1 hora: ${t.titulo}')}',
      'TRIGGER:-PT1H',
      'END:VALARM',
      'END:VEVENT',
      'END:VCALENDAR',
    ];
    return '${linhas.map(dobrar).join('\r\n')}\r\n';
  }

  /// TEXT da RFC 5545 (3.3.11): barra, ponto e vírgula, vírgula e quebra de
  /// linha escapados.
  static String escapar(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\n', '\\n');

  /// Linhas de até 75 octetos (3.1): o resto continua na linha seguinte,
  /// começando com um espaço. Conta bytes UTF-8 e nunca corta um caractere
  /// ao meio — "ç" e "—" têm mais de um byte.
  static String dobrar(String linha) {
    if (utf8.encode(linha).length <= 75) return linha;
    final partes = <String>[];
    final atual = StringBuffer();
    var bytes = 0;
    var limite = 75;
    for (final rune in linha.runes) {
      final c = String.fromCharCode(rune);
      final n = utf8.encode(c).length;
      if (bytes + n > limite) {
        partes.add(atual.toString());
        atual.clear();
        bytes = 0;
        limite = 74; // a linha de continuação já gasta um octeto no espaço
      }
      atual.write(c);
      bytes += n;
    }
    partes.add(atual.toString());
    return partes.join('\r\n ');
  }

  static String _local(DateTime d) =>
      '${d.year}${_doisDigitos(d.month)}${_doisDigitos(d.day)}T${_doisDigitos(d.hour)}${_doisDigitos(d.minute)}${_doisDigitos(d.second)}';

  static String _utc(DateTime d) => '${_local(d.toUtc())}Z';

  static String _doisDigitos(int n) => n.toString().padLeft(2, '0');
}
