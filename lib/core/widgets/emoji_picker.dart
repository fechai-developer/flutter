import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Seletor de emoji: presets + opção de digitar qualquer emoji pelo teclado
/// (ex.: 🎄 no Natal). Usado em grupos e assinaturas. (#3)
class EmojiPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final List<String> presets;

  const EmojiPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.presets = groupEmojis,
  });

  static const List<String> groupEmojis = [
    '🏖️', '🏠', '🍺', '✈️', '🎉', '🍕', '⚽', '🎬', '💸', '🚗',
    '🏔️', '🎸', '🏕️', '🍔', '🎂', '🎄', '🎃', '🎁', '🐶', '❤️',
  ];
  static const List<String> subscriptionEmojis = [
    '🎬', '🎵', '💻', '📺', '🎮', '📱', '☁️', '📚', '🏋️', '🔒',
    '🎧', '📰', '🛒', '🍿', '🤖', '✏️', '🧠', '💳',
  ];

  Future<void> _pickCustom(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _CustomEmojiDialog(),
    );
    if (result != null && result.isNotEmpty) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Garante que o emoji atual apareça mesmo se for custom (fora dos presets).
    final all = <String>[if (!presets.contains(value)) value, ...presets];

    Widget cell({required Widget child, required bool selected, required VoidCallback onTap}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: selected ? AppColors.mentaViva.withValues(alpha: 0.4) : theme.cardTheme.color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.verdeAguaProfundo : AppColors.areiaNeutra,
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in all)
          cell(
            selected: e == value,
            onTap: () => onChanged(e),
            child: Text(e, style: const TextStyle(fontSize: 24)),
          ),
        cell(
          selected: false,
          onTap: () => _pickCustom(context),
          child: Icon(Icons.emoji_emotions_outlined, color: AppColors.verdeAguaProfundo),
        ),
      ],
    );
  }
}

/// Mantém só o primeiro emoji/grafema digitado (#4).
class _SingleGraphemeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final chars = newValue.text.characters;
    if (chars.length <= 1) return newValue;
    final first = chars.take(1).toString();
    return TextEditingValue(text: first, selection: TextSelection.collapsed(offset: first.length));
  }
}

/// Diálogo de emoji custom: hint aleatório trocando a cada 2s (transparente,
/// para não parecer preenchido) e limite de 1 emoji. (#4)
class _CustomEmojiDialog extends StatefulWidget {
  const _CustomEmojiDialog();

  @override
  State<_CustomEmojiDialog> createState() => _CustomEmojiDialogState();
}

class _CustomEmojiDialogState extends State<_CustomEmojiDialog> {
  final _controller = TextEditingController();
  final _rand = Random();
  Timer? _timer;
  String _hint = '🎄';

  static const _pool = [
    '🎄', '🎃', '🎁', '🐶', '🐱', '🍺', '🍕', '⚽', '🏀', '🎮',
    '✈️', '🏝️', '🎸', '📚', '💡', '🌟', '🔥', '🍔', '🚀', '🎯',
  ];

  @override
  void initState() {
    super.initState();
    _hint = _pool[_rand.nextInt(_pool.length)];
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_controller.text.isEmpty && mounted) {
        setState(() => _hint = _pool[_rand.nextInt(_pool.length)]);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Digite um emoji'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 40),
        inputFormatters: [_SingleGraphemeFormatter()],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          counterText: '',
          hintText: _hint,
          // Transparente para deixar claro que é só sugestão, não preenchido.
          hintStyle: TextStyle(fontSize: 40, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.22)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _controller.text.trim().isEmpty ? null : () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Usar'),
        ),
      ],
    );
  }
}
