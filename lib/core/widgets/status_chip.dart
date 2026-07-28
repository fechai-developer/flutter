import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Chip compacto de status para bater o olho em listas (grupos/assinaturas).
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const StatusChip({super.key, required this.label, required this.color, required this.icon});

  /// Tudo quitado / encerrado — neutro, discreto.
  factory StatusChip.settled() => const StatusChip(
        label: 'Quitado',
        color: Color(0xFF8FA39E),
        icon: Icons.check_circle_outline,
      );

  /// Sem lançamentos ainda.
  factory StatusChip.empty() => const StatusChip(
        label: 'Sem lançamentos',
        color: Color(0xFF8FA39E),
        icon: Icons.inbox_outlined,
      );

  factory StatusChip.toReceive() => const StatusChip(
        label: 'A receber',
        color: AppColors.verdeAguaProfundo,
        icon: Icons.arrow_downward,
      );

  factory StatusChip.toPay() => const StatusChip(
        label: 'Você deve',
        color: AppColors.coralAceso,
        icon: Icons.arrow_upward,
      );

  factory StatusChip.overdue() => const StatusChip(
        label: 'Em atraso',
        color: AppColors.coralAceso,
        icon: Icons.error_outline,
      );

  factory StatusChip.pending() => const StatusChip(
        label: 'Acerto pendente',
        color: Color(0xFFB78A2E),
        icon: Icons.schedule,
      );

  factory StatusChip.recurring() => const StatusChip(
        label: 'Recorrente',
        color: AppColors.verdeAguaProfundo,
        icon: Icons.repeat,
      );

  /// Fui removido — só tenho acesso ao histórico (leitura).
  factory StatusChip.archived() => const StatusChip(
        label: 'Arquivado',
        color: Color(0xFF8FA39E),
        icon: Icons.lock_outline,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
