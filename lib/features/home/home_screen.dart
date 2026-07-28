import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/icons.dart';

import '../../core/utils/balance.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/member_name.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/user_name.dart';
import '../../core/widgets/wave_card.dart';
import '../../data/models/expense_group.dart';
import '../../data/models/person.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/app_repository.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';
import '../caixinha/create_caixinha_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final groups = ref.watch(groupsProvider);
    final subs = ref.watch(subscriptionsProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(groupsProvider);
            ref.invalidate(subscriptionsProvider);
            ref.invalidate(pendingInvitesProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // Cabeçalho
              Row(
                children: [
                  Expanded(
                    child: user.when(
                      data: (u) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Olá,', style: theme.textTheme.bodyMedium),
                          Text(u.name, style: userNameStyle(context, base: theme.textTheme.headlineMedium)),
                        ],
                      ),
                      loading: () => const SizedBox(height: 48),
                      error: (_, __) => const Text('Olá!'),
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.push('/resumo'),
                    tooltip: 'Resumo',
                    icon: Icon(AppIcons.chartBar, color: AppColors.verdeAguaProfundo),
                  ),
                  IconButton(
                    onPressed: () => context.push('/profile'),
                    icon: user.maybeWhen(
                      data: (u) => MemberAvatar.person(u, size: 40),
                      orElse: () => const CircleAvatar(radius: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Convites pendentes de aceite (#1)
              const _PendingInvitesBanner(),

              // Card de saldo (gradiente + corte de onda) — assinatura visual
              _BalanceCard(groups: groups, subs: subs),
              const SizedBox(height: 28),

              // Atalhos
              Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: AppIcons.usersThree,
                      label: 'Nova conta',
                      onTap: () => context.go('/groups/new'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickAction(
                      icon: AppIcons.repeat,
                      label: 'Nova assinatura',
                      onTap: () => context.go('/subscriptions/new'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickAction(
                      icon: AppIcons.piggyBank,
                      label: 'Nova caixinha',
                      onTap: () => showCreateCaixinhaSheet(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Pendências de assinatura (próximos vencimentos / atrasos)
              _PendingSubscriptions(subs: subs),
              const SizedBox(height: 28),

              // Feed de atividade recente (#5)
              _ActivityFeed(groups: groups),
            ],
          ),
        ),
      ),
    );
  }
}

String _who(String? name) => (name == null || name == 'Você') ? 'Você' : name.split(' ').first;

/// Feed de atividade recente: despesas lançadas e acertos, de qualquer pessoa
/// dos seus grupos. Tocar leva ao grupo. (#5)
///
/// Mostra até [_pageSize] itens numa área rolável de altura fixa; "Carregar
/// mais" revela o próximo lote (base para paginar no banco depois).
class _ActivityFeed extends StatefulWidget {
  final AsyncValue<List<ExpenseGroup>> groups;
  const _ActivityFeed({required this.groups});

  @override
  State<_ActivityFeed> createState() => _ActivityFeedState();
}

class _ActivityFeedState extends State<_ActivityFeed> {
  static const int _pageSize = 7;
  int _visible = _pageSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = widget.groups.valueOrNull ?? const [];
    final items = <_Activity>[];
    for (final g in list) {
      for (final e in g.expenses) {
        final payer = g.memberById(e.paidByPersonId);
        final bool? credit = e.paidByPersonId == 'me'
            ? true
            : (e.shares.containsKey('me') ? false : null);
        items.add(_Activity(
          date: e.date,
          icon: AppIcons.receipt,
          segments: [(_who(payer?.name), true), (' lançou ${e.description}', false)],
          subtitle: g.name,
          amount: e.amount,
          groupId: g.id,
          credit: credit,
        ));
      }
      for (final p in g.payments) {
        final from = g.memberById(p.fromId);
        final to = g.memberById(p.toId);
        final bool? credit = p.toId == 'me' ? true : (p.fromId == 'me' ? false : null);
        items.add(_Activity(
          date: p.date,
          icon: AppIconsFill.handCoins,
          segments: [(_who(from?.name), true), (' acertou com ', false), (_who(to?.name), true)],
          subtitle: g.name,
          amount: p.amount,
          groupId: g.id,
          isPayment: true,
          credit: credit,
        ));
      }
    }
    items.sort((a, b) => b.date.compareTo(a.date));

    if (items.isEmpty) return const SizedBox.shrink();

    final visible = _visible.clamp(0, items.length);
    final shown = items.take(visible).toList();
    final hasMore = items.length > visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Atividade recente', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        // Altura fixa (~7 cards) com rolagem interna.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 384),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            itemCount: shown.length,
            itemBuilder: (context, i) => _activityRow(context, shown[i]),
          ),
        ),
        if (hasMore) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _visible += _pageSize),
              child: Text('Carregar mais (${items.length - visible})'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            _legend(context, AppColors.verdeAguaProfundo, 'a receber'),
            const SizedBox(width: 16),
            _legend(context, AppColors.coralAceso, 'a pagar'),
          ],
        ),
      ],
    );
  }

  Widget _activityRow(BuildContext context, _Activity a) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/groups/${a.groupId}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (a.isPayment ? AppColors.mentaViva : AppColors.verdeAguaProfundo).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(a.icon, size: 18, color: AppColors.verdeAguaProfundo),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        for (final (text, isName) in a.segments)
                          isName
                              ? userNameSpan(context, text, base: theme.textTheme.bodyMedium)
                              : TextSpan(text: text, style: theme.textTheme.bodyMedium),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(a.subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (a.credit != null) ...[
                Icon(
                  a.credit! ? AppIconsFill.arrowDown : AppIconsFill.arrowUp,
                  size: 13,
                  color: a.credit! ? AppColors.verdeAguaProfundo : AppColors.coralAceso,
                ),
                const SizedBox(width: 2),
              ],
              MoneyText(
                a.amount,
                fontSize: 14,
                color: a.credit == null
                    ? null
                    : (a.credit! ? AppColors.verdeAguaProfundo : AppColors.coralAceso),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legend(BuildContext context, Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(c == AppColors.coralAceso ? AppIconsFill.arrowUp : AppIconsFill.arrowDown, size: 12, color: c),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _Activity {
  final DateTime date;
  final IconData icon;
  final List<(String, bool)> segments; // (texto, éNome)
  final String subtitle;
  final double amount;
  final String groupId;
  final bool isPayment;
  final bool? credit; // true=a receber, false=a pagar, null=não me envolve
  const _Activity({
    required this.date,
    required this.icon,
    required this.segments,
    required this.subtitle,
    required this.amount,
    required this.groupId,
    this.isPayment = false,
    this.credit,
  });
}

/// Lista de convites (#1, Etapa C) — aparece no topo da Home após o login.
/// Não-aceitos aparecem primeiro; pendentes com Aceitar/Recusar, recusados
/// esmaecidos e ainda acionáveis (dá pra aceitar depois — item 6).
class _PendingInvitesBanner extends ConsumerWidget {
  const _PendingInvitesBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(pendingInvitesProvider).valueOrNull ?? const [];
    if (all.isEmpty) return const SizedBox.shrink();
    // Pendentes primeiro, recusados por último.
    final invites = [...all]..sort((a, b) {
        final av = a.isDeclined ? 1 : 0;
        final bv = b.isDeclined ? 1 : 0;
        return av.compareTo(bv);
      });
    return Column(
      children: [for (final inv in invites) _InviteCard(invite: inv)],
    );
  }
}

class _InviteCard extends ConsumerWidget {
  final PendingInvite invite;
  const _InviteCard({required this.invite});

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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: declined
            ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
            : AppColors.mentaViva.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: declined
              ? AppColors.areiaNeutra
              : AppColors.verdeAguaProfundo.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(opacity: declined ? 0.55 : 1, child: Text(invite.emoji, style: const TextStyle(fontSize: 24))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      invite.kind == 'group' ? 'Convite de conta' : 'Convite de assinatura',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (declined) ...[
                      const SizedBox(width: 6),
                      const MemberStatusChip(MemberStatus.declined),
                    ],
                  ],
                ),
                Text(invite.title, style: theme.textTheme.titleMedium),
                if (declined)
                  Text('Você recusou este convite.', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Ações à direita: Aceitar em cima, Recusar logo abaixo.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.verdeAguaProfundo,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: () => _accept(context, ref),
                child: Text(declined ? 'Aceitar assim mesmo' : 'Aceitar'),
              ),
              if (!declined)
                TextButton(
                  onPressed: () => _decline(context, ref),
                  child: Text('Recusar', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final AsyncValue<List<ExpenseGroup>> groups;
  final AsyncValue<List<Subscription>> subs;
  const _BalanceCard({required this.groups, required this.subs});

  @override
  Widget build(BuildContext context) {
    // Saldo consolidado do usuário: a receber (grupos onde é credor +
    // cotas de assinatura pendentes que é dono) − a pagar.
    double toReceive = 0;
    double toPay = 0;

    groups.whenData((list) {
      for (final g in list) {
        final net = BalanceCalculator.netBalances(g)['me'] ?? 0;
        if (net > 0) toReceive += net;
        if (net < 0) toPay += -net;
      }
    });
    subs.whenData((list) {
      for (final s in list) {
        if (s.ownerId == 'me') {
          toReceive += s.pendingThisCycle;
        } else {
          final mine = s.members.where((m) => m.person.id == 'me' && m.status != QuotaStatus.paid);
          for (final m in mine) {
            toPay += m.quota;
          }
        }
      }
    });

    final net = toReceive - toPay;

    return GestureDetector(
      onTap: () => context.go('/charge'),
      child: WaveCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  net >= 0 ? 'Você tem a receber' : 'Você deve no total',
                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text('Acertar', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w600)),
                Icon(AppIcons.caretRight, size: 16, color: Colors.white.withValues(alpha: 0.85)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              Money.format(net.abs()),
              style: AppTheme.moneyStyle(fontSize: 40, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _MiniStat(label: 'A receber', value: toReceive, icon: AppIconsFill.arrowDown),
                const SizedBox(width: 24),
                _MiniStat(label: 'A pagar', value: toPay, icon: AppIconsFill.arrowUp),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  const _MiniStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(
              Money.format(value),
              style: AppTheme.moneyStyle(fontSize: 15, color: Colors.white),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardTheme.color,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: AppColors.areiaNeutra),
            boxShadow: AppTheme.softShadow(),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.verdeAguaProfundo, size: 26),
              const SizedBox(height: 8),
              Text(label, style: theme.textTheme.labelLarge, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingSubscriptions extends StatelessWidget {
  final AsyncValue<List<Subscription>> subs;
  const _PendingSubscriptions({required this.subs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return subs.when(
      skipLoadingOnReload: true, // mantém o bloco visível durante a rebusca
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      error: (e, _) => Text('Erro: $e'),
      data: (list) {
        final pending = list.where((s) => s.pendingThisCycle > 0).toList();
        if (pending.isEmpty) {
          return _EmptyHint(
            icon: AppIcons.checkCircle,
            text: 'Tudo em dia com as assinaturas 🎉',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Precisa cobrar', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Cotas pendentes neste ciclo', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            for (final s in pending)
              _PendingRow(sub: s),
          ],
        );
      },
    );
  }
}

class _PendingRow extends StatelessWidget {
  final Subscription sub;
  const _PendingRow({required this.sub});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = sub.members.any((m) => m.status == QuotaStatus.overdue);
    final pendingCount = sub.members.where((m) => m.status != QuotaStatus.paid).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          onTap: () => context.go('/subscriptions/${sub.id}'),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: overdue ? AppColors.coralAceso.withValues(alpha: 0.5) : AppColors.areiaNeutra),
            ),
            child: Row(
              children: [
                Text(sub.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sub.serviceName, style: theme.textTheme.titleMedium),
                      Text(
                        overdue
                            ? '$pendingCount pendente(s) · há atraso'
                            : '$pendingCount cota(s) a receber',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: overdue ? AppColors.coralAceso : null,
                        ),
                      ),
                    ],
                  ),
                ),
                MoneyText(sub.pendingThisCycle, fontSize: 16, color: overdue ? AppColors.coralAceso : AppColors.verdeAguaProfundo),
                const SizedBox(width: 4),
                Icon(AppIcons.caretRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.mentaViva),
          const SizedBox(height: 12),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
