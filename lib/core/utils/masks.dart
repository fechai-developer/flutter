import 'package:flutter/services.dart';

/// Máscara de telefone BR: (11) 99999-8888. Guarda só dígitos internamente;
/// use [digitsOf] para extrair o número limpo.
class BrPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 11) d = d.substring(0, 11);

    final b = StringBuffer();
    for (int i = 0; i < d.length; i++) {
      if (i == 0) b.write('(');
      if (i == 2) b.write(') ');
      if (i == 7) b.write('-'); // celular (9 dígitos) → separa antes dos 4 finais
      b.write(d[i]);
    }
    final text = b.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

String digitsOf(String s) => s.replaceAll(RegExp(r'\D'), '');

/// "Você" é reservado para o usuário logado — não deixar ninguém usar como nome
/// (confunde a interface). (#8)
bool isReservedName(String name) {
  final n = name.trim().toLowerCase();
  return n == 'você' || n == 'voce';
}

/// Normaliza uma chave PIX digitada (com máscara) para o valor real:
/// e-mail como está, CPF só dígitos, celular como +55DDDNUMERO, aleatória como está.
String normalizePixKey(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  if (t.contains('@')) return t; // e-mail
  final d = digitsOf(t);
  if (t.contains('(')) return '+55$d'; // celular (máscara com parênteses)
  if (t.contains('.') && d.length == 11) return d; // CPF (máscara com pontos)
  return t; // aleatória / já normalizada
}

/// Formata um telefone (só dígitos, com ou sem DDI) para exibição BR.
String formatPhone(String? digits) {
  if (digits == null) return '';
  var d = digitsOf(digits);
  if (d.startsWith('55') && d.length > 11) d = d.substring(2); // tira DDI
  if (d.length < 10) return d;
  final ddd = d.substring(0, 2);
  final rest = d.substring(2);
  if (rest.length == 9) return '($ddd) ${rest.substring(0, 5)}-${rest.substring(5)}';
  return '($ddd) ${rest.substring(0, 4)}-${rest.substring(4)}';
}
