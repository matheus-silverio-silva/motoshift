// O backend passou a devolver o perfil de outra conta sem os dados pessoais
// (documento, CNH, nascimento, e-mail, telefone, endereço). O app lê esse
// perfil na tela do turno do lojista para mostrar quem aceitou.

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/usuario.dart';

void main() {
  test('perfil público sem e-mail e telefone não derruba o parse', () {
    final usuario = Usuario.fromJson({
      'id': 7,
      'nome': 'Ricardo Souza',
      'tipo': 'motoboy',
      'cidade': 'Curitiba',
      'estado': 'PR',
      'score': 4.7,
      'mediaAvaliacao': 4.8,
      'veiculoModelo': 'Honda CG 160 Titan',
      'veiculoCor': 'Vermelha',
    });

    expect(usuario.nome, 'Ricardo Souza');
    expect(usuario.score, 4.7);
    expect(usuario.veiculoModelo, 'Honda CG 160 Titan');
    expect(usuario.email, isEmpty);
    expect(usuario.telefone, isEmpty);
    expect(usuario.documentoFederal, isNull);
    expect(usuario.cnhNumero, isNull);
  });

  test('perfil completo continua lendo e-mail e telefone', () {
    final usuario = Usuario.fromJson({
      'id': 7,
      'nome': 'Ricardo Souza',
      'email': 'ricardo@teste.com',
      'telefone': '(41) 98111-2222',
      'tipo': 'motoboy',
      'documentoFederal': '12345678900',
    });

    expect(usuario.email, 'ricardo@teste.com');
    expect(usuario.telefone, '(41) 98111-2222');
    expect(usuario.documentoFederal, '12345678900');
  });
}
