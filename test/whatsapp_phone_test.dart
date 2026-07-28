import 'package:flutter_test/flutter_test.dart';
import 'package:fechai/core/utils/whatsapp.dart';

void main() {
  group('WhatsApp.normalizePhone', () {
    test('prefixa DDI 55 em celular sem DDI', () {
      expect(WhatsApp.normalizePhone('11999998888'), '5511999998888');
      expect(WhatsApp.normalizePhone('(11) 99999-8888'), '5511999998888');
    });

    test('prefixa DDI 55 em fixo (10 dígitos)', () {
      expect(WhatsApp.normalizePhone('1133334444'), '551133334444');
    });

    test('mantém número que já tem DDI 55', () {
      expect(WhatsApp.normalizePhone('5511999998888'), '5511999998888');
      expect(WhatsApp.normalizePhone('+55 (11) 99999-8888'), '5511999998888');
    });

    test('vazio quando não há número', () {
      expect(WhatsApp.normalizePhone(null), '');
      expect(WhatsApp.normalizePhone(''), '');
    });
  });

  group('WhatsApp.buildUri', () {
    test('usa o número normalizado no wa.me', () {
      final uri = WhatsApp.buildUri(message: 'oi', phone: '11999998888');
      expect(uri.toString(), startsWith('https://wa.me/5511999998888?text='));
    });

    test('abre sem destinatário quando não há número', () {
      final uri = WhatsApp.buildUri(message: 'oi');
      expect(uri.toString(), startsWith('https://wa.me/?text='));
    });
  });
}
