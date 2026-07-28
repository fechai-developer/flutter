import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons.dart';
import 'create_caixinha_screen.dart';
import '../../core/widgets/invite_actions.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models/caixinha.dart';
import '../../data/models/person.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';

/// Lista das caixinhas (poupança coletiva) das quais você participa.
class CaixinhasListScreen extends ConsumerWidget {
  const CaixinhasListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caixinhas = ref.watch(caixinhasProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Caixinhas')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_caixinhas',
        onPressed: () => showCreateCaixinhaSheet(context),
        backgroundColor: AppColors.verdeAguaProfundo,
        foregroundColor: Colors.white,
        icon: Icon(AppIcons.plus),
        label: const Text('Nova'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(caixinhasProvider),
        child: caixinhas.when(
          skipLoadingOnReload: true, // mantém a lista visível durante a rebusca
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erro: $e')),
          data: (list) {
            if (list.isEmpty) return const _EmptyCaixinhas();
            final sorted = [...list]..sort((a, b) {
                if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1; // abertas primeiro
                return b.createdAt.compareTo(a.createdAt);
              });
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (int i = 0; i < sorted.length; i++) ...[
                  _CaixinhaCard(caixinha: sorted[i]),
                  if (i < sorted.length - 1) const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CaixinhaCard extends ConsumerWidget {
  final Caixinha caixinha;
  const _CaixinhaCard({required this.caixinha});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = caixinha;
    if (c.memberById('me')?.isBorrower ?? false) return _borrowerCard(context, c);
    final myShare = c.balanceOf('me');
    final myPct = c.participationOf('me');
    final invite = inviteFor(ref, kind: 'caixinha', sourceId: c.id);

    return Opacity(
      opacity: c.isClosed ? 0.7 : 1,
      child: Material(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          onTap: () => context.go('/caixinhas/${c.id}'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: AppColors.areiaNeutra),
              boxShadow: c.isClosed ? null : AppTheme.softShadow(),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.mentaViva.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(c.emoji, style: const TextStyle(fontSize: 26)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: theme.textTheme.titleLarge),
                          Text('${c.memberCount} membros · juros ${_pct(c.defaultInterestPct)}',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(height: 6),
                          _Avatars(people: c.members.map((m) => m.person).toList()),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        c.isClosed ? StatusChip.settled() : StatusChip.toReceive(),
                        const SizedBox(height: 8),
                        MoneyText(c.patrimony, fontSize: 16),
                        Text('patrimônio', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.mentaViva.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(AppIcons.piggyBank, size: 16, color: AppColors.verdeAguaProfundo),
                      const SizedBox(width: 8),
                      Text('Sua parte', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      MoneyText(myShare, fontSize: 15),
                      const SizedBox(width: 6),
                      Text('(${(myPct * 100).toStringAsFixed(0)}%)', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (invite != null) InviteActionBar(invite),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Card quando o usuário é apenas TOMADOR externo desta caixinha: mostra só o
  /// que ele deve, sem patrimônio/participação dos outros.
  Widget _borrowerCard(BuildContext context, Caixinha c) {
    final theme = Theme.of(context);
    final owed = c.loans.where((l) => l.borrowerPersonId == 'me').fold(0.0, (a, l) => a + c.outstandingOf(l));
    return Material(
      color: theme.cardTheme.color,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: () => context.go('/caixinhas/${c.id}'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: AppColors.areiaNeutra),
            boxShadow: AppTheme.softShadow(),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: AppColors.mentaViva.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Text(c.emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: theme.textTheme.titleLarge),
                    Text('Seu empréstimo', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('você deve', style: theme.textTheme.bodySmall),
                  MoneyText(owed, fontSize: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _pct(double v) => '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)}%';

class _Avatars extends StatelessWidget {
  final List<Person> people;
  const _Avatars({required this.people});

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

class _EmptyCaixinhas extends StatelessWidget {
  const _EmptyCaixinhas();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(AppIcons.piggyBank, size: 64, color: AppColors.mentaViva),
        const SizedBox(height: 16),
        Text('Organize sua caixinha', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Sua família ou grupo já junta uma graninha todo mês? Organize por aqui! '
          'Acompanhe quanto cada um já tem e os rendimentos ao longo do tempo — '
          'tudo transparente, sem depender do caderninho.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}
