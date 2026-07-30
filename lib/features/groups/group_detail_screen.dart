import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/icons.dart';

import '../../core/categories.dart';
import '../../core/utils/balance.dart';
import '../../core/utils/currency.dart';
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
import 'group_indicators_tab.dart';
import 'widgets/mini_calendar.dart';

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
        length: 3,
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
              tabs: [Tab(text: 'Saldos'), Tab(text: 'Despesas'), Tab(text: 'Indicadores')],
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
              GroupIndicatorsTab(group: g, meId: me.valueOrNull?.id ?? 'me'),
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

    // Item 1: o que EU (logado) representei nesta conta — "Sua parte" (soma do
    // que me coube no rateio) e "Você pagou" (despesas em que fui o pagador).
    double minhaParte = 0;
    double euPaguei = 0;
    for (final e in group.expenses) {
      minhaParte += e.shares[meId] ?? 0;
      if (e.paidByPersonId == meId) euPaguei += e.amount;
    }

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
        if (group.expenses.isNotEmpty) ...[
          const SizedBox(height: 12),
          _YouInGroupCard(minhaParte: minhaParte, euPaguei: euPaguei),
        ],
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

/// Item 1: resumo do PRÓPRIO usuário dentro da conta — "Sua parte" (consumo que
/// coube a mim) e "Você pagou" (o que saiu do meu bolso). Dá pra bater o olho e
/// entender os dois lados sem abrir a lista de despesas.
class _YouInGroupCard extends StatelessWidget {
  final double minhaParte;
  final double euPaguei;
  const _YouInGroupCard({required this.minhaParte, required this.euPaguei});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.userCircle, size: 18, color: AppColors.verdeAguaProfundo),
              const SizedBox(width: 8),
              Text('Você nesta conta', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _YouStat(
                  label: 'Sua parte',
                  hint: 'o que te coube',
                  value: minhaParte,
                  color: AppColors.verdeAguaProfundo,
                ),
              ),
              const SizedBox(width: 16),
              Container(width: 1, height: 40, color: AppColors.areiaNeutra),
              const SizedBox(width: 16),
              Expanded(
                child: _YouStat(
                  label: 'Você pagou',
                  hint: 'saiu do seu bolso',
                  value: euPaguei,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YouStat extends StatelessWidget {
  final String label;
  final String hint;
  final double value;
  final Color color;
  const _YouStat({required this.label, required this.hint, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        MoneyText(value, fontSize: 20, color: color),
        Text(hint, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
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

    // Botões compactos: valor + duas ações precisam caber lado a lado no celular.
    final compactButton = ButtonStyle(
      padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 8)),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: WidgetStatePropertyAll(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );

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
          // Faixa 1: avatares + seta + "Fulano paga Ciclano" (nome + sobrenome).
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
                    userNameSpan(context, iPay ? 'Você' : from.fullName, base: theme.textTheme.bodyMedium),
                    TextSpan(text: ' paga ', style: theme.textTheme.bodySmall),
                    userNameSpan(context, iReceive ? 'você' : to.fullName, base: theme.textTheme.bodyMedium),
                  ]),
                ),
              ),
            ],
          ),
          // Faixa 2: valor + ações. Só as duas pessoas envolvidas podem acertar
          // (#6): botões aparecem quando "eu" (meId) sou pagador ou recebedor.
          const SizedBox(height: 12),
          Row(
            children: [
              MoneyText(settlement.amount, fontSize: 16, color: AppColors.coralAceso),
              const Spacer(),
              if (iReceive) ...[
                FilledButton.icon(
                  style: compactButton,
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
                  icon: Icon(AppIconsFill.handCoins, size: 16),
                  label: const Text('Cobrar'),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  style: compactButton,
                  onPressed: onSettle,
                  icon: Icon(AppIcons.check, size: 16),
                  label: const Text('Recebido'),
                ),
              ] else if (iPay)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.verdeAguaProfundo).merge(compactButton),
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
                  icon: Icon(AppIcons.qrCode, size: 16),
                  label: const Text('Pagar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Como a lista de despesas é organizada (item 3).
enum _ExpGroupBy { none, date, type }

/// Uma seção da lista agrupada: cabeçalho opcional + subtotal + itens.
class _Section {
  final String? label;
  final IconData? icon;
  final double subtotal;
  final List<Expense> items;
  const _Section({this.label, this.icon, required this.subtotal, required this.items});
}

class _ExpensesTab extends ConsumerStatefulWidget {
  final ExpenseGroup group;
  const _ExpensesTab({required this.group});

  @override
  ConsumerState<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends ConsumerState<_ExpensesTab> {
  _ExpGroupBy _groupBy = _ExpGroupBy.none;
  bool _sortAsc = false; // false = mais recentes / maiores primeiro
  bool _calendarOpen = false;
  DateTime? _selectedDay;

  ExpenseGroup get group => widget.group;

  Future<void> _edit(Expense e) async {
    final result = await showExpenseSheet(context, group: group, existing: e);
    if (result == null) return;
    final controller = ref.read(repositoryControllerProvider);
    if (result.deleted) {
      await controller.deleteExpense(group.id, e.id);
    } else if (result.expense != null) {
      await controller.updateExpense(group.id, result.expense!);
    }
  }

  /// Constrói as seções conforme agrupamento/ordenação e o filtro de dia.
  List<_Section> _buildSections(List<Expense> source) {
    final list = _selectedDay == null
        ? source
        : source.where((e) => dayKey(e.date) == dayKey(_selectedDay!)).toList();

    int dir(num a, num b) => _sortAsc ? a.compareTo(b) : b.compareTo(a);

    switch (_groupBy) {
      case _ExpGroupBy.none:
        final items = [...list]..sort((a, b) => dir(a.date.millisecondsSinceEpoch, b.date.millisecondsSinceEpoch));
        return [_Section(subtotal: items.fold(0.0, (s, e) => s + e.amount), items: items)];

      case _ExpGroupBy.date:
        final byDay = <DateTime, List<Expense>>{};
        for (final e in list) {
          byDay.putIfAbsent(dayKey(e.date), () => []).add(e);
        }
        final keys = byDay.keys.toList()..sort((a, b) => dir(a.millisecondsSinceEpoch, b.millisecondsSinceEpoch));
        final df = DateFormat("EEE, d 'de' MMM", 'pt_BR');
        return [
          for (final k in keys)
            _Section(
              label: _cap(df.format(k)),
              icon: AppIconsFill.calendarBlank,
              subtotal: byDay[k]!.fold(0.0, (s, e) => s + e.amount),
              items: byDay[k]!..sort((a, b) => b.amount.compareTo(a.amount)),
            ),
        ];

      case _ExpGroupBy.type:
        final byType = <String, List<Expense>>{};
        for (final e in list) {
          final key = (e.category == null || e.category!.trim().isEmpty) ? kNoCategoryLabel : e.category!.trim();
          byType.putIfAbsent(key, () => []).add(e);
        }
        final entries = byType.entries.toList()
          ..sort((a, b) {
            final sa = a.value.fold<double>(0, (s, e) => s + e.amount);
            final sb = b.value.fold<double>(0, (s, e) => s + e.amount);
            return dir(sa, sb);
          });
        return [
          for (final e in entries)
            _Section(
              label: e.key,
              icon: categoryIcon(e.key == kNoCategoryLabel ? null : e.key),
              subtotal: e.value.fold(0.0, (s, x) => s + x.amount),
              items: e.value..sort((a, b) => b.amount.compareTo(a.amount)),
            ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
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

    final markedDays = {for (final e in group.expenses) dayKey(e.date)};
    final sections = _buildSections(group.expenses);

    final calendar = _calendarOpen
        ? MiniCalendar(
            initialMonth: _selectedDay ?? group.expenses.first.date,
            markedDays: markedDays,
            selectedDay: _selectedDay,
            onDaySelected: (d) => setState(() => _selectedDay = d),
          )
        : null;

    final listContent = _buildListBody(sections);

    return Column(
      children: [
        _controls(theme),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 900;
              if (wide && calendar != null) {
                // Computador: calendário à esquerda, lista à direita.
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 320,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 8, 20),
                        child: calendar,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: listContent),
                  ],
                );
              }
              // Celular: gaveta no topo empurra a lista pra baixo.
              return Column(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: calendar == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                            child: calendar,
                          ),
                  ),
                  Expanded(child: listContent),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _controls(ThemeData theme) {
    Widget seg(String label, _ExpGroupBy value) {
      final selected = _groupBy == value;
      return GestureDetector(
        onTap: () => setState(() => _groupBy = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.verdeAguaProfundo : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.areiaNeutra),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  seg('Lista', _ExpGroupBy.none),
                  seg('Data', _ExpGroupBy.date),
                  seg('Tipo', _ExpGroupBy.type),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _iconToggle(
            icon: _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
            tooltip: _sortAsc ? 'Crescente' : 'Decrescente',
            active: false,
            onTap: () => setState(() => _sortAsc = !_sortAsc),
          ),
          const SizedBox(width: 8),
          _iconToggle(
            icon: kCalendarIcon,
            tooltip: 'Calendário',
            active: _calendarOpen || _selectedDay != null,
            onTap: () => setState(() => _calendarOpen = !_calendarOpen),
          ),
        ],
      ),
    );
  }

  Widget _iconToggle({required IconData icon, required String tooltip, required bool active, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active ? AppColors.verdeAguaProfundo : theme.cardTheme.color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? AppColors.verdeAguaProfundo : AppColors.areiaNeutra),
          ),
          child: Icon(icon, size: 20, color: active ? Colors.white : theme.colorScheme.onSurface.withValues(alpha: 0.75)),
        ),
      ),
    );
  }

  Widget _buildListBody(List<_Section> sections) {
    final theme = Theme.of(context);
    final children = <Widget>[];

    // "Resumo do dia por tipo" quando um dia está selecionado (item 5).
    if (_selectedDay != null) {
      children.add(_DayResumo(
        day: _selectedDay!,
        expenses: group.expenses.where((e) => dayKey(e.date) == dayKey(_selectedDay!)).toList(),
        onClear: () => setState(() => _selectedDay = null),
      ));
    }

    final hasHeaders = _groupBy != _ExpGroupBy.none;
    final anyItems = sections.any((s) => s.items.isNotEmpty);

    if (!anyItems) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text('Nada neste filtro', style: theme.textTheme.bodyMedium)),
      ));
    }

    for (final s in sections) {
      if (s.items.isEmpty) continue;
      if (hasHeaders) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(
            children: [
              if (s.icon != null) ...[
                Icon(s.icon, size: 16, color: AppColors.verdeAguaProfundo),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(s.label ?? '', style: theme.textTheme.titleMedium)),
              Text(Money.format(s.subtotal), style: AppTheme.moneyStyle(fontSize: 13, color: AppColors.textoSuave)),
            ],
          ),
        ));
      }
      for (var i = 0; i < s.items.length; i++) {
        children.add(_expenseRow(s.items[i]));
        if (i < s.items.length - 1) children.add(const Divider(height: 1));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      children: children,
    );
  }

  Widget _expenseRow(Expense e) {
    final theme = Theme.of(context);
    final df = DateFormat("d 'de' MMM", 'pt_BR');
    final payer = group.memberById(e.paidByPersonId);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: group.viewerRemoved ? null : () => _edit(e),
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
              child: Icon(categoryIcon(e.category), color: AppColors.verdeAguaProfundo, size: 22),
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
                    e.category != null && e.category!.trim().isNotEmpty
                        ? '${payer?.name ?? '?'} pagou · ${df.format(e.date)} · ${e.category}'
                        : '${payer?.name ?? '?'} pagou · ${df.format(e.date)}',
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
  }
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Resumo do dia selecionado: total + quebra por tipo em chips. (Itens 4/5)
class _DayResumo extends StatelessWidget {
  final DateTime day;
  final List<Expense> expenses;
  final VoidCallback onClear;
  const _DayResumo({required this.day, required this.expenses, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat("EEE, d 'de' MMMM", 'pt_BR');
    final total = expenses.fold<double>(0, (s, e) => s + e.amount);
    final byType = <String, double>{};
    for (final e in expenses) {
      final key = (e.category == null || e.category!.trim().isEmpty) ? kNoCategoryLabel : e.category!.trim();
      byType[key] = (byType[key] ?? 0) + e.amount;
    }
    final entries = byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.mentaViva.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(_cap(df.format(day)), style: theme.textTheme.titleMedium)),
              MoneyText(total, fontSize: 16),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Limpar dia',
                onPressed: onClear,
                icon: Icon(AppIcons.close, size: 18),
              ),
            ],
          ),
          if (expenses.isEmpty)
            Text('Sem despesas neste dia', style: theme.textTheme.bodySmall)
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final e in entries)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.cardTheme.color,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.areiaNeutra),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(categoryIcon(e.key == kNoCategoryLabel ? null : e.key), size: 14, color: AppColors.verdeAguaProfundo),
                        const SizedBox(width: 6),
                        Text(e.key, style: theme.textTheme.bodySmall),
                        const SizedBox(width: 6),
                        Text(Money.format(e.value), style: AppTheme.moneyStyle(fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
