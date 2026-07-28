import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/icons.dart';

import '../../core/utils/currency.dart';
import '../../core/widgets/filter_bar.dart';
import '../../core/widgets/invite_actions.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models/person.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';

class SubscriptionsListScreen extends ConsumerStatefulWidget {
  const SubscriptionsListScreen({super.key});

  @override
  ConsumerState<SubscriptionsListScreen> createState() => _SubscriptionsListScreenState();
}

String subStatusLabel(Subscription s) {
  if (s.viewerRemoved) return 'Arquivado';
  if (s.activeMembers.any((m) => m.status == QuotaStatus.overdue)) return 'Em atraso';
  if (s.pendingThisCycle > 0.009) return 'A receber';
  return 'Quitado';
}

const _subStatuses = ['Em atraso', 'A receber', 'Quitado', 'Arquivado'];

class _SubscriptionsListScreenState extends ConsumerState<SubscriptionsListScreen> {
  String _query = '';
  Set<String> _people = {};
  String? _status;

  @override
  Widget build(BuildContext context) {
    final subs = ref.watch(subscriptionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Assinaturas')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_subscriptions',
        onPressed: () => context.go('/subscriptions/new'),
        backgroundColor: AppColors.verdeAguaProfundo,
        foregroundColor: Colors.white,
        icon: Icon(AppIcons.plus),
        label: const Text('Nova'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(subscriptionsProvider);
          ref.invalidate(pendingInvitesProvider);
        },
        child: subs.when(
        skipLoadingOnReload: true, // mantém a lista visível durante a rebusca
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (raw) {
          if (raw.isEmpty) return const _EmptySubs();
          final list = [...raw]..sort((a, b) => _subPriority(a).compareTo(_subPriority(b)));
          final people = <String>{
            for (final s in raw)
              for (final m in s.members)
                if (m.person.id != 'me') m.person.name
          }.toList()
            ..sort();
          final filtered = list.where((s) {
            if (_query.isNotEmpty && !s.serviceName.toLowerCase().contains(_query.toLowerCase())) return false;
            if (_people.isNotEmpty && !s.members.any((m) => _people.contains(m.person.name))) return false;
            if (_status != null && subStatusLabel(s) != _status) return false;
            return true;
          }).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              FilterBar(
                onQueryChanged: (v) => setState(() => _query = v),
                people: people,
                selectedPeople: _people,
                onPeopleChanged: (s) => setState(() => _people = s),
                statuses: _subStatuses,
                selectedStatus: _status,
                onStatusChanged: (s) => setState(() => _status = s),
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(child: Text('Nenhuma assinatura encontrada', style: Theme.of(context).textTheme.bodyMedium)),
                ),
              for (int i = 0; i < filtered.length; i++) ...[
                _SubCard(sub: filtered[i]),
                if (i < filtered.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
      ),
    );
  }
}

int _subPriority(Subscription s) {
  if (s.viewerRemoved) return 3; // arquivadas por último
  if (s.activeMembers.any((m) => m.status == QuotaStatus.overdue)) return 0; // atraso
  if (s.pendingThisCycle > 0.009) return 1; // a receber
  return 2; // ciclo quitado
}

class _SubCard extends ConsumerWidget {
  final Subscription sub;
  const _SubCard({required this.sub});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final invite = inviteFor(ref, kind: 'subscription', sourceId: sub.id);
    final archived = sub.viewerRemoved;
    final progress = sub.quotaCount == 0 ? 0.0 : sub.filledQuotas / sub.quotaCount;
    final overdue = sub.activeMembers.any((m) => m.status == QuotaStatus.overdue);
    final settled = _subPriority(sub) == 2;
    final dim = settled || archived;

    return Opacity(
      opacity: dim ? 0.68 : 1,
      child: Material(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          onTap: () => context.go('/subscriptions/${sub.id}'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: AppColors.areiaNeutra),
              boxShadow: dim ? null : AppTheme.softShadow(),
            ),
            child: Column(
              children: [
                Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.mentaViva.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(sub.emoji, style: const TextStyle(fontSize: 26)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sub.serviceName, style: theme.textTheme.titleLarge),
                        Text('Vence dia ${sub.billingDay} · ${sub.filledQuotas}/${sub.quotaCount} cotas',
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 6),
                        _SubAvatars(people: sub.activeMembers.map((m) => m.person).toList()),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Chip de status no topo-direito, consistente com os grupos.
                      archived
                          ? StatusChip.archived()
                          : overdue
                              ? StatusChip.overdue()
                              : (sub.pendingThisCycle > 0.009 ? StatusChip.toReceive() : StatusChip.settled()),
                      const SizedBox(height: 8),
                      MoneyText(sub.totalAmount, fontSize: 16),
                      Text('${Money.format(sub.quotaValue)}/cota', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.areiaNeutra,
                  valueColor: const AlwaysStoppedAnimation(AppColors.verdeAguaProfundo),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    overdue ? AppIconsFill.warningCircle : AppIcons.clockCountdown,
                    size: 14,
                    color: overdue ? AppColors.coralAceso : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    overdue
                        ? 'Há cotas em atraso'
                        : (sub.pendingThisCycle > 0 ? '${Money.format(sub.pendingThisCycle)} a receber' : 'Ciclo quitado'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: overdue ? AppColors.coralAceso : null,
                    ),
                  ),
                ],
              ),
              if (invite != null) InviteActionBar(invite),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pilha compacta de avatares dos participantes da assinatura (paridade com o
/// card de grupo) — mostra de relance quem divide a assinatura.
class _SubAvatars extends StatelessWidget {
  final List<Person> people;
  const _SubAvatars({required this.people});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = people.take(4).toList();
    final overflow = people.length - shown.length;
    return Row(
      children: [
        SizedBox(
          width: 18.0 * shown.length + 8,
          height: 24,
          child: Stack(
            children: [
              for (int i = 0; i < shown.length; i++)
                Positioned(
                  left: i * 16.0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.cardTheme.color ?? Colors.white, width: 1.5),
                    ),
                    child: MemberAvatar.person(shown[i], size: 22),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          overflow > 0 ? '+$overflow' : '${people.length} ${people.length == 1 ? 'pessoa' : 'pessoas'}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _EmptySubs extends StatelessWidget {
  const _EmptySubs();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.repeat, size: 64, color: AppColors.mentaViva),
            const SizedBox(height: 16),
            Text('Nenhuma assinatura', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Cadastre o streaming ou serviço que\nvocê divide e cobre as cotas todo mês.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
