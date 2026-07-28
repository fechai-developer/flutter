import 'package:flutter/material.dart';

import '../icons.dart';
import '../../theme/app_theme.dart';

/// Gaveta expansível: um cabeçalho tocável (ícone + título) que revela/esconde
/// o conteúdo. Usado para deixar QR Code e mensagem "escondidos por padrão",
/// mostrando de cara só o essencial (PIX copia e cola).
class ExpandableTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;
  const ExpandableTile({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  State<ExpandableTile> createState() => _ExpandableTileState();
}

class _ExpandableTileState extends State<ExpandableTile> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _open = !_open),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.areiaNeutra),
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: 20, color: AppColors.verdeAguaProfundo),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Icon(_open ? AppIcons.caretUp : AppIcons.caretDown,
                      size: 22, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: widget.child,
          ),
          crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }
}
