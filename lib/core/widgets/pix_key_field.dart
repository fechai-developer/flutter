import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/masks.dart';
import '../../theme/app_theme.dart';

enum PixType { cpf, celular, email, aleatoria }

extension _PixLabel on PixType {
  String get label => switch (this) {
        PixType.cpf => 'CPF',
        PixType.celular => 'Celular',
        PixType.email => 'E-mail',
        PixType.aleatoria => 'Aleatória',
      };
}

class _CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 11) d = d.substring(0, 11);
    final b = StringBuffer();
    for (int i = 0; i < d.length; i++) {
      if (i == 3 || i == 6) b.write('.');
      if (i == 9) b.write('-');
      b.write(d[i]);
    }
    final t = b.toString();
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

/// Campo de chave PIX com seletor de tipo, máscara e validação simples (#3).
/// [controller] recebe o valor final da chave (com máscara para CPF/celular).
class PixKeyField extends StatefulWidget {
  final TextEditingController controller;
  const PixKeyField({super.key, required this.controller});

  @override
  State<PixKeyField> createState() => _PixKeyFieldState();
}

class _PixKeyFieldState extends State<PixKeyField> {
  PixType _type = PixType.celular;

  String? _validate(String v) {
    final t = v.trim();
    if (t.isEmpty) return null; // vazio é permitido (só não recebe cobrança)
    switch (_type) {
      case PixType.cpf:
        return digitsOf(t).length == 11 ? null : 'CPF deve ter 11 dígitos';
      case PixType.celular:
        final d = digitsOf(t);
        return (d.length == 10 || d.length == 11) ? null : 'Telefone incompleto';
      case PixType.email:
        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'E-mail inválido';
      case PixType.aleatoria:
        return t.length >= 16 ? null : 'Chave aleatória parece curta';
    }
  }

  List<TextInputFormatter> get _formatters => switch (_type) {
        PixType.cpf => [_CpfInputFormatter()],
        PixType.celular => [BrPhoneInputFormatter()],
        _ => const [],
      };

  TextInputType get _keyboard => switch (_type) {
        PixType.cpf || PixType.celular => TextInputType.number,
        PixType.email => TextInputType.emailAddress,
        PixType.aleatoria => TextInputType.text,
      };

  String get _hint => switch (_type) {
        PixType.cpf => '000.000.000-00',
        PixType.celular => '(11) 99999-8888',
        PixType.email => 'voce@email.com',
        PixType.aleatoria => 'cole a chave aleatória',
      };

  @override
  Widget build(BuildContext context) {
    final error = _validate(widget.controller.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in PixType.values)
              ChoiceChip(
                label: Text(t.label),
                selected: _type == t,
                selectedColor: AppColors.mentaViva.withValues(alpha: 0.4),
                onSelected: (_) => setState(() {
                  _type = t;
                  widget.controller.clear();
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: widget.controller,
          keyboardType: _keyboard,
          inputFormatters: _formatters,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: _hint,
            errorText: error,
          ),
        ),
      ],
    );
  }
}
