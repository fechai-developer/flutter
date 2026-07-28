import 'package:flutter_test/flutter_test.dart';
import 'package:fechai/core/utils/pix.dart';

// Recalcula o CRC16-CCITT sobre o payload sem os 4 dígitos finais, para
// validar de forma independente que o gerador fecha o BR Code corretamente.
String crc16(String payload) {
  const polynomial = 0x1021;
  int crc = 0xFFFF;
  for (final c in payload.codeUnits) {
    crc ^= (c << 8) & 0xFFFF;
    for (int i = 0; i < 8; i++) {
      if ((crc & 0x8000) != 0) {
        crc = ((crc << 1) ^ polynomial) & 0xFFFF;
      } else {
        crc = (crc << 1) & 0xFFFF;
      }
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}

void main() {
  group('PixPayload.build', () {
    test('gera BR Code estruturalmente válido com valor', () {
      final code = PixPayload.build(
        pixKey: 'voce@email.com',
        merchantName: 'FULANO DE TAL',
        merchantCity: 'SAO PAULO',
        amount: 13.98,
      );

      // Payload Format Indicator
      expect(code.startsWith('000201'), isTrue);
      // GUI do PIX
      expect(code.contains('0014BR.GOV.BCB.PIX'), isTrue);
      // Moeda BRL e valor formatado com ponto
      expect(code.contains('5303986'), isTrue);
      expect(code.contains('540513.98'), isTrue); // 54 + len 05 + "13.98"
      // País
      expect(code.contains('5802BR'), isTrue);
      // Termina com o campo CRC (6304 + 4 hex)
      expect(RegExp(r'6304[0-9A-F]{4}$').hasMatch(code), isTrue);
    });

    test('CRC final confere com cálculo independente', () {
      final code = PixPayload.build(
        pixKey: '11999998888',
        merchantName: 'MARIA',
        merchantCity: 'RIO',
        amount: 100.00,
      );
      final withoutCrc = code.substring(0, code.length - 4);
      final expected = crc16(withoutCrc);
      expect(code.endsWith(expected), isTrue);
    });

    test('sem valor usa iniciação reutilizável (010211) e omite campo 54', () {
      final code = PixPayload.build(
        pixKey: 'chave',
        merchantName: 'X',
        merchantCity: 'Y',
      );
      expect(code.contains('010211'), isTrue);
      expect(code.contains('5303986'), isTrue);
      // não deve conter campo de valor
      expect(code.contains('5405'), isFalse);
    });
  });
}
