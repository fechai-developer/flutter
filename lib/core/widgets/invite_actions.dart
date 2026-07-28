import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/person.dart';
import '../../data/repositories/app_repository.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';
import 'member_name.dart';

/// Barra de ação de convite exibida nos cards das listas de grupo/assinatura
/// quando o usuário foi convidado e ainda não aceitou (Etapa C, item 5).
/// Pendente → Aceitar/Recusar; recusado → tag "Recusado" + aceitar depois.
class InviteActionBar extends ConsumerWidget {
  final PendingInvite invite;
  const InviteActionBar(this.invite, {super.key});

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    await ref.read(repositoryControllerProvider).acceptInvite(invite);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Você entrou em ${invite.title} ✅'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    await ref.read(repositoryControllerProvider).declineInvite(invite);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Convite de ${invite.title} recusado'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final declined = invite.isDeclined;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          if (declined) ...[
            const MemberStatusChip(MemberStatus.declined),
            const SizedBox(width: 8),
            Expanded(child: Text('Você recusou este convite.', style: theme.textTheme.bodySmall)),
          ] else
            Expanded(
              child: Text('Você foi convidado para participar.', style: theme.textTheme.bodySmall),
            ),
          if (!declined) ...[
            TextButton(
              onPressed: () => _decline(context, ref),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: Text('Recusar', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            ),
            const SizedBox(width: 4),
          ],
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.verdeAguaProfundo,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () => _accept(context, ref),
            child: const Text('Aceitar'),
          ),
        ],
      ),
    );
  }
}

/// Procura o convite (pendente ou recusado) referente a um grupo/assinatura.
PendingInvite? inviteFor(WidgetRef ref, {required String kind, required String sourceId}) {
  final invites = ref.watch(pendingInvitesProvider).valueOrNull ?? const [];
  for (final i in invites) {
    if (i.kind == kind && i.sourceId == sourceId) return i;
  }
  return null;
}
