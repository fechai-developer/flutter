import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../data/models/person.dart';
import '../../theme/app_theme.dart';
import 'member_avatar.dart';
import 'member_name.dart';
import 'sheet_handle.dart';

/// Dados mínimos de um participante para exibição (nome + situação do convite).
class ParticipantInfo {
  final String name; // primeiro nome
  final String? lastName; // sobrenome
  final bool isMe;
  final MemberStatus status;
  const ParticipantInfo({required this.name, this.lastName, required this.isMe, required this.status});

  /// Nome completo "Nome Sobrenome" (só o primeiro quando não há sobrenome).
  String get fullName {
    final l = lastName?.trim() ?? '';
    return l.isEmpty ? name : '$name $l';
  }
}

/// Faixa "Participantes" — mostra de forma objetiva quem está no grupo/assinatura:
/// avatares empilhados + contagem, e ao tocar abre a lista completa com o status
/// de cada um (aceito / aguardando / recusado). Reutilizável em grupo e assinatura.
class ParticipantsStrip extends StatelessWidget {
  final List<ParticipantInfo> participants;
  final String title;
  const ParticipantsStrip({super.key, required this.participants, this.title = 'Participantes'});

  int get _accepted => participants.where((p) => p.status == MemberStatus.accepted).length;
  bool get _hasPending => participants.any((p) => p.status != MemberStatus.accepted);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = participants.take(5).toList();
    final overflow = participants.length - shown.length;

    return Material(
      color: theme.cardTheme.color,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: () => _openList(context),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: AppColors.areiaNeutra),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24.0 * shown.length + (overflow > 0 ? 24 : 4),
                height: 34,
                child: Stack(
                  children: [
                    for (int i = 0; i < shown.length; i++)
                      Positioned(
                        left: i * 20.0,
                        child: Opacity(
                          opacity: shown[i].status == MemberStatus.declined ? 0.5 : 1,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.cardTheme.color ?? Colors.white, width: 2),
                            ),
                            child: MemberAvatar(name: shown[i].name, lastName: shown[i].lastName, size: 34),
                          ),
                        ),
                      ),
                    if (overflow > 0)
                      Positioned(
                        left: shown.length * 20.0,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.mentaViva.withValues(alpha: 0.3),
                            border: Border.all(color: theme.cardTheme.color ?? Colors.white, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: Text('+$overflow',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.verdeAguaProfundo)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    Text(
                      _hasPending
                          ? '${participants.length} no total · $_accepted já aceitaram'
                          : '${participants.length} pessoas',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.caretRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }

  void _openList(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 20),
              Text('$title (${participants.length})', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final p in participants)
                DeclinedDim(
                  declined: p.status == MemberStatus.declined,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        MemberAvatar(name: p.name, lastName: p.lastName, size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MemberName(
                            p.isMe ? 'Você' : p.fullName,
                            status: p.status,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                          ),
                        ),
                        MemberStatusChip(p.status),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
