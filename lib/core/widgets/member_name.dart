import 'package:flutter/material.dart';

import '../../data/models/person.dart';
import 'pending_badge.dart';
import 'user_name.dart';

/// Nome de um membro conforme a situação do convite (Etapa C, itens 6/9).
///
/// - [MemberStatus.accepted]: nome real, sublinhado (as duas pessoas já "se
///   conhecem" no app) — usa [UserName].
/// - [MemberStatus.pending] / [MemberStatus.declined]: mostra o nome **digitado
///   por quem convidou entre "aspas"** e esmaecido, sinalizando que ainda não é
///   o nome que a própria pessoa definiu.
class MemberName extends StatelessWidget {
  final String name;
  final MemberStatus status;
  final TextStyle? style;
  final int? maxLines;
  const MemberName(
    this.name, {
    super.key,
    required this.status,
    this.style,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    if (status == MemberStatus.accepted) {
      return UserName(name, style: style, maxLines: maxLines);
    }
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text(
      '"$name"',
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
      style: base.copyWith(
        fontStyle: FontStyle.italic,
        color: base.color?.withValues(alpha: 0.6) ??
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }
}

/// Indicador do status do convite — sinal de não-aceitação que independe das
/// aspas do nome (dois conhecidos podem não ter aceitado ainda):
/// - pendente: ampulheta com tooltip "Aguardando o aceite do convite";
/// - recusado: tag "Recusado".
/// Some quando o membro já aceitou.
class MemberStatusChip extends StatelessWidget {
  final MemberStatus status;
  const MemberStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MemberStatus.pending:
        return const PendingBadge();
      case MemberStatus.declined:
        final muted = Theme.of(context).colorScheme.onSurface;
        return _StatusTag(
          label: 'Recusado',
          icon: Icons.block_rounded,
          fg: muted.withValues(alpha: 0.6),
          bg: muted.withValues(alpha: 0.08),
        );
      case MemberStatus.accepted:
        return const SizedBox.shrink();
    }
  }
}

class _StatusTag extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  const _StatusTag({required this.label, required this.icon, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

/// Wrapper que aplica o "overlay cinza" (esmaecimento) em membros recusados,
/// mantendo a linha legível mas visualmente rebaixada (Etapa C, item 6).
class DeclinedDim extends StatelessWidget {
  final bool declined;
  final Widget child;
  const DeclinedDim({super.key, required this.declined, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!declined) return child;
    return Opacity(opacity: 0.55, child: child);
  }
}
