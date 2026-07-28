import 'package:flutter/material.dart';

/// Selo de "aguardando aceite do convite" — ampulheta com tooltip (hover/clique).
/// Sinaliza que o membro ainda não aceitou o grupo/assinatura (Etapa C).
class PendingBadge extends StatelessWidget {
  final double size;
  const PendingBadge({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Aguardando o aceite do convite',
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(Icons.hourglass_top_rounded, size: size, color: const Color(0xFFB78A2E)),
      ),
    );
  }
}
