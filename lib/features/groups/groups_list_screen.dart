import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/icons.dart';

import '../../core/utils/balance.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/filter_bar.dart';
import '../../core/widgets/invite_actions.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models/expense_group.dart';
import '../../data/models/person.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';

class GroupsListScreen extends ConsumerStatefulWidget {
  const GroupsListScreen({super.key});

  @override
  ConsumerState<GroupsListScreen> createState() => _GroupsListScreenState();
}

/// Rótulo de status do grupo (mesma lógica do chip) — usado no filtro.
String groupStatusLabel(ExpenseGroup g) {
  if (g.viewerRemoved) return 'Arquivado';
  final my = BalanceCalculator.netBalances(g)['me'] ?? 0;
  if (g.expenses.isEmpty) return 'Sem lançamentos';
  if (my > 0.009) return 'A receber';
  if (my < -0.009) return 'Você deve';
  if (groupPriority(g) == 1) return 'Acerto pendente';
  return 'Quitado';
}

const _groupStatuses = ['A receber', 'Você deve', 'Acerto pendente', 'Quitado', 'Sem lançamentos', 'Arquivado'];

class _GroupsListScreenState extends ConsumerState<GroupsListScreen> {
  String _query = '';
  Set<String> _people = {};
  String? _status;

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Contas')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_groups',
        onPressed: () => context.go('/groups/new'),
        backgroundColor: AppColors.verdeAguaProfundo,
        foregroundColor: Colors.white,
        icon: Icon(AppIcons.plus),
        label: const Text('Nova conta'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(groupsProvider);
          ref.invalidate(pendingInvitesProvider);
        },
        child: groups.when(
        skipLoadingOnReload: true, // mantém a lista visível durante a rebusca
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (raw) {
          if (raw.isEmpty) {
            return const _EmptyGroups();
          }
          // Ordena por atenção: o que me envolve primeiro, quitado por último.
          final list = [...raw]..sort((a, b) => groupPriority(a).compareTo(groupPriority(b)));
          // Pessoas disponíveis para o filtro (nomes únicos, exceto "Você").
          final people = <String>{
            for (final g in raw)
              for (final m in g.members)
                if (m.id != 'me') m.name
          }.toList()
            ..sort();
          final filtered = list.where((g) {
            if (_query.isNotEmpty && !g.name.toLowerCase().contains(_query.toLowerCase())) return false;
            if (_people.isNotEmpty && !g.members.any((m) => _people.contains(m.name))) return false;
            if (_status != null && groupStatusLabel(g) != _status) return false;
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
                statuses: _groupStatuses,
                selectedStatus: _status,
                onStatusChanged: (s) => setState(() => _status = s),
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(child: Text('Nenhuma conta encontrada', style: Theme.of(context).textTheme.bodyMedium)),
                ),
              for (int i = 0; i < filtered.length; i++) ...[
                _GroupCard(group: filtered[i]),
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

/// Prioridade para ordenar a lista (0 = mais atenção). Usada também para dimming.
int groupPriority(ExpenseGroup g) {
  if (g.viewerRemoved) return 4; // arquivados por último
  final my = BalanceCalculator.netBalances(g)['me'] ?? 0;
  final open = BalanceCalculator.simplify(g).isNotEmpty;
  if (g.expenses.isEmpty) return 2; // sem lançamentos
  if (open && my.abs() > 0.009) return 0; // me envolve
  if (open) return 1; // acerto entre outros
  return 3; // tudo quitado
}

class _GroupCard extends ConsumerWidget {
  final ExpenseGroup group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final invite = inviteFor(ref, kind: 'group', sourceId: group.id);
    final archived = group.viewerRemoved;
    final myBalance = BalanceCalculator.netBalances(group)['me'] ?? 0;
    final prio = groupPriority(group);
    final settled = prio == 3;
    final dim = settled || archived;
    final empty = group.expenses.isEmpty;
    final hasRecurring = group.expenses.any((e) => e.isRecurring);
    final peopleCount = group.activeMembers.length;

    final StatusChip statusChip = archived
        ? StatusChip.archived()
        : empty
            ? StatusChip.empty()
            : myBalance > 0.009
                ? StatusChip.toReceive()
                : myBalance < -0.009
                    ? StatusChip.toPay()
                    : prio == 1
                        ? StatusChip.pending()
                        : StatusChip.settled();

    return Opacity(
      opacity: dim ? 0.68 : 1, // quitados/arquivados ficam discretos
      child: Material(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          onTap: () => context.go('/groups/${group.id}'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: AppColors.areiaNeutra),
              boxShadow: dim ? null : AppTheme.softShadow(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.mentaViva.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(group.emoji, style: const TextStyle(fontSize: 26)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(group.name, style: theme.textTheme.titleLarge, overflow: TextOverflow.ellipsis)),
                          if (hasRecurring) ...[
                            const SizedBox(width: 6),
                            Icon(AppIcons.repeat, size: 15, color: AppColors.verdeAguaProfundo),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _AvatarStack(people: group.activeMembers),
                          const SizedBox(width: 8),
                          Text('$peopleCount pessoas', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Tag no topo-direito + saldo abaixo (sem criar linha extra). (#3)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    statusChip,
                    if (!empty && !archived && myBalance.abs() > 0.009) ...[
                      const SizedBox(height: 8),
                      MoneyText.byBalance(myBalance, fontSize: 16),
                    ],
                  ],
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

class _AvatarStack extends StatelessWidget {
  final List<Person> people;
  const _AvatarStack({required this.people});

  @override
  Widget build(BuildContext context) {
    final shown = people.take(3).toList();
    return SizedBox(
      width: 24.0 * shown.length + 4,
      height: 28,
      child: Stack(
        children: [
          for (int i = 0; i < shown.length; i++)
            Positioned(
              left: i * 20.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).cardTheme.color ?? Colors.white, width: 2),
                ),
                child: MemberAvatar.person(shown[i], size: 24),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.usersThree, size: 64, color: AppColors.mentaViva),
            const SizedBox(height: 16),
            Text('Nenhuma conta ainda', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Crie uma conta pra dividir as despesas\nda viagem, do rolê ou da casa.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
