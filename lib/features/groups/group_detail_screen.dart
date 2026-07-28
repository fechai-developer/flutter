import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/icons.dart';

import '../../core/utils/balance.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/participants_strip.dart';
import '../../core/widgets/user_name.dart';
import '../../data/models/expense.dart';
import '../../data/models/expense_group.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';
import '../charge/charge_sheet.dart';
import '../charge/pay_sheet.dart';
import 'edit_group_sheet.dart';
import 'expense_sheet.dart';

class GroupDetailScreen extends ConsumerWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupByIdProvider(groupId));
    final me = ref.watch(currentUserProvider);

    return group.when(
      // Mantém a tela atual visível enquanto rebusca (ex.: evento de realtime
      // invalida a lista da qual este detalhe depende) — sem piscar em branco.
      skipLoadingOnReload: true,
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Erro: $e'))),
      data: (g) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: Icon(AppIcons.arrowLeft),
              onPressed: () => context.go('/groups'),
            ),
            title: Row(
              children: [
                Text(g.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Flexible(child: Text(g.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
            actions: [
              if (!g.viewerRemoved)
                IconButton(
                  icon: Icon(AppIcons.pencilSimple),
                  tooltip: 'Editar conta',
                  onPressed: () => showEditGroupSheet(context, ref, g),
                ),
            ],
            bottom: const TabBar(
              labelColor: AppColors.verdeAguaProfundo,
              indicatorColor: AppColors.verdeAguaProfundo,
              tabs: [Tab(text: 'Saldos'), Tab(text: 'Despesas')],
            ),
          ),
          floatingActionButton: g.viewerRemoved
              ? null
              : FloatingActionButton.extended(
                  heroTag: 'fab_group_detail',
                  onPressed: () => _addExpense(context, ref, g),
                  backgroundColor: AppColors.verdeAguaProfundo,
                  foregroundColor: Colors.white,
                  icon: Icon(AppIcons.plus),
                  label: const Text('Despesa'),
                ),
          body: TabBarView(
            children: [
              _BalancesTab(group: g, meId: me.valueOrNull?.id ?? 'me'),
              _ExpensesTab(group: g),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addExpense(BuildContext context, WidgetRef ref, ExpenseGroup g) async {
    final result = await showExpenseSheet(context, group: g);
    if (result?.expense != null) {
      await ref.read(repositoryControllerProvider).addExpense(g.id, result!.expense!);
    }
  }

}

/// Aviso mostrado quando o usuário logado foi removido do grupo: acesso
/// somente-leitura ao histórico das despesas em que se envolveu.
class _RemovedBanner extends StatelessWidget {
  const _RemovedBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.areiaNeutra.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.lock, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Você não faz mais parte desta conta. Aqui fica só o histórico '
              'das despesas em que você se envolveu.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso no topo dos Saldos (dono) quando há recorrência afetada por uma saída.
/// - [hasPayerLeft]: quem pagava saiu → **precisa** reatribuir (coral).
/// - só participante saiu → a próxima já será redividida sozinha; abrir é
///   opcional, só se quiser ajustar (âmbar).
class _RecurrenceReviewBanner extends StatelessWidget {
  final bool hasPayerLeft;
  const _RecurrenceReviewBanner({required this.hasPayerLeft});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = hasPayerLeft ? AppColors.coralAceso : const Color(0xFFB78A2E);
    final text = hasPayerLeft
        ? 'Quem pagava uma despesa recorrente saiu. Abra-a em "Despesas" e '
            'escolha quem passa a pagar antes da próxima cobrança.'
        : 'Uma despesa recorrente tinha alguém que saiu. A próxima cobrança já '
            'será redividida entre quem ficou — abra em "Despesas" só se quiser ajustar.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.repeat, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// Pílula de aviso numa despesa recorrente afetada por uma saída.
/// - payerLeft: bloqueia a próxima geração até reatribuir quem paga (coral).
/// - participantLeft: a próxima ocorrência será redividida entre os ativos (âmbar).
class _RecurrenceReviewPill extends StatelessWidget {
  final RecurrenceReview review;
  const _RecurrenceReviewPill({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payer = review == RecurrenceReview.payerLeft;
    final color = payer ? AppColors.coralAceso : const Color(0xFFB78A2E);
    final label = payer
        ? 'Revisar: quem pagava saiu'
        : 'Recorrência será redividida (alguém saiu)';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.warningCircle, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _BalancesTab extends ConsumerWidget {
  final ExpenseGroup group;
  final String meId;
  const _BalancesTab({required this.group, required this.meId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settlements = BalanceCalculator.simplify(group);
    final me = ref.watch(currentUserProvider).valueOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      children: [
        if (group.viewerRemoved) ...[
          const _RemovedBanner(),
          const SizedBox(height: 12),
        ],
        if (!group.viewerRemoved && group.isOwner &&
            group.expenses.any((e) => e.needsRecurrenceReview)) ...[
          _RecurrenceReviewBanner(
            hasPayerLeft: group.expenses.any((e) => e.recurrenceReview == RecurrenceReview.payerLeft),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.mentaViva.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          child: Row(
            children: [
              Icon(AppIconsFill.receipt, color: AppColors.verdeAguaProfundo),
              const SizedBox(width: 12),
              Text('Total da conta', style: theme.textTheme.titleMedium),
              const Spacer(),
              MoneyText(group.total, fontSize: 20),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Quem está no grupo — visível e objetivo (toque abre a lista com status).
        ParticipantsStrip(
          participants: [
            for (final m in group.activeMembers)
              ParticipantInfo(
                name: m.id == 'me' ? 'Você' : m.name,
                lastName: m.id == 'me' ? null : m.lastName,
                isMe: m.id == 'me',
                status: group.statusOf(m.id),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Quem paga quem', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Simplificamos pra menos transferências possível.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (settlements.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(AppIcons.checkCircle, size: 48, color: AppColors.mentaViva),
                const SizedBox(height: 12),
                Text('Contas quitadas 🎉', style: theme.textTheme.titleMedium),
              ],
            ),
          )
        else
          for (final s in settlements)
            _SettlementRow(
              group: group,
              settlement: s,
              meId: meId,
              mePixKey: me?.pixKey ?? '',
              meName: me?.name ?? 'Você',
              onSettle: () async {
                await ref.read(repositoryControllerProvider).settleUp(
                      group.id,
                      fromId: s.fromPersonId,
                      toId: s.toPersonId,
                      amount: s.amount,
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Acerto registrado ✅'), behavior: SnackBarBehavior.floating),
                  );
                }
              },
            ),
      ],
    );
  }
}

class _SettlementRow extends ConsumerWidget {
  final ExpenseGroup group;
  final Settlement settlement;
  final String meId;
  final String mePixKey;
  final String meName;
  final VoidCallback onSettle;

  const _SettlementRow({
    required this.group,
    required this.settlement,
    required this.meId,
    required this.mePixKey,
    required this.meName,
    required this.onSettle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final from = group.memberById(settlement.fromPersonId);
    final to = group.memberById(settlement.toPersonId);
    if (from == null || to == null) return const SizedBox.shrink();

    final iReceive = settlement.toPersonId == meId; // alguém me paga
    final iPay = settlement.fromPersonId == meId; // eu pago alguém

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Column(
        children: [
          Row(
            children: [
              MemberAvatar.person(from, size: 34),
              const SizedBox(width: 8),
              Icon(AppIcons.caretRight, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(width: 8),
              MemberAvatar.person(to, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    userNameSpan(context, iPay ? 'Você' : from.name, base: theme.textTheme.bodyMedium),
                    TextSpan(text: ' paga ', style: theme.textTheme.bodySmall),
                    userNameSpan(context, iReceive ? 'você' : to.name, base: theme.textTheme.bodyMedium),
                  ]),
                ),
              ),
              MoneyText(settlement.amount, fontSize: 16, color: AppColors.coralAceso),
            ],
          ),
          // Só as duas pessoas envolvidas podem acertar (#6): aqui, só quando
          // "eu" (meId) sou o pagador ou o recebedor da transferência.
          if (iReceive) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final paid = await showChargeSheet(
                        context,
                        ChargeRequest(
                          fromName: meName,
                          fromPixKey: mePixKey,
                          toName: from.name,
                          toLastName: from.lastName,
                          toPhone: from.phone,
                          amount: settlement.amount,
                          reason: group.name,
                        ),
                      );
                      if (paid == true) onSettle();
                    },
                    icon: Icon(AppIconsFill.handCoins, size: 18),
                    label: const Text('Cobra Aí'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onSettle,
                  icon: Icon(AppIcons.check, size: 18),
                  label: const Text('Já recebi'),
                ),
              ],
            ),
          ] else if (iPay) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.verdeAguaProfundo),
                onPressed: () async {
                  final pix = to.pixKey ??
                      await ref.read(repositoryControllerProvider).memberPixKey(group.id, to.id);
                  if (!context.mounted) return;
                  final paid = await showPaySheet(
                    context,
                    PayRequest(
                      toName: to.name,
                      toLastName: to.lastName,
                      toPixKey: pix,
                      amount: settlement.amount,
                      reason: group.name,
                    ),
                  );
                  if (paid == true) onSettle();
                },
                icon: Icon(AppIcons.qrCode, size: 18),
                label: const Text('Pagar'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpensesTab extends ConsumerWidget {
  final ExpenseGroup group;
  const _ExpensesTab({required this.group});

  Future<void> _edit(BuildContext context, WidgetRef ref, Expense e) async {
    final result = await showExpenseSheet(context, group: group, existing: e);
    if (result == null) return;
    final controller = ref.read(repositoryControllerProvider);
    if (result.deleted) {
      await controller.deleteExpense(group.id, e.id);
    } else if (result.expense != null) {
      await controller.updateExpense(group.id, result.expense!);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (group.expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.receipt, size: 56, color: AppColors.mentaViva),
            const SizedBox(height: 12),
            Text('Nenhuma despesa lançada', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Toque no + para lançar a primeira.', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }
    final df = DateFormat("d 'de' MMM", 'pt_BR');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      itemCount: group.expenses.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = group.expenses[i];
        final payer = group.memberById(e.paidByPersonId);
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: group.viewerRemoved ? null : () => _edit(context, ref, e),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.mentaViva.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(AppIcons.receipt, color: AppColors.verdeAguaProfundo, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(e.description, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                          if (e.isRecurring) ...[
                            const SizedBox(width: 6),
                            Icon(AppIcons.repeat, size: 14, color: AppColors.verdeAguaProfundo),
                          ],
                        ],
                      ),
                      Text(
                        '${payer?.name ?? '?'} pagou · ${df.format(e.date)} · ${e.type.label}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (e.needsRecurrenceReview) _RecurrenceReviewPill(review: e.recurrenceReview),
                    ],
                  ),
                ),
                MoneyText(e.amount, fontSize: 16),
                const SizedBox(width: 4),
                Icon(AppIcons.caretRight, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.35)),
              ],
            ),
          ),
        );
      },
    );
  }
}
