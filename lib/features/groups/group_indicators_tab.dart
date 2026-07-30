import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/icons.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/money_text.dart';
import '../../data/models/expense_group.dart';
import '../../theme/app_theme.dart';
import '../stats/category_breakdown.dart';
import 'widgets/mini_calendar.dart';

/// Aba "Indicadores" de uma conta: número de dias, gasto médio por dia/despesa,
/// quebra por tipo e destaques. Tudo calculado no cliente sobre group.expenses.
class GroupIndicatorsTab extends StatelessWidget {
  final ExpenseGroup group;
  final String meId;
  const GroupIndicatorsTab({super.key, required this.group, required this.meId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expenses = group.expenses;

    if (expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.chartBar, size: 56, color: AppColors.mentaViva),
            const SizedBox(height: 12),
            Text('Ainda sem indicadores', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Lance despesas pra ver os números da conta.', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    final total = group.total;
    double minhaParte = 0;
    for (final e in expenses) {
      minhaParte += e.shares[meId] ?? 0;
    }

    // Dias distintos com despesa + período (min→max, inclusive).
    final dayTotals = <DateTime, double>{};
    for (final e in expenses) {
      final k = dayKey(e.date);
      dayTotals[k] = (dayTotals[k] ?? 0) + e.amount;
    }
    final distinctDays = dayTotals.length;
    final sortedDays = dayTotals.keys.toList()..sort();
    final minDate = sortedDays.first;
    final maxDate = sortedDays.last;
    final periodDays = maxDate.difference(minDate).inDays + 1;

    final avgPerDay = distinctDays == 0 ? 0.0 : total / distinctDays;
    final avgPerExpense = total / expenses.length;

    final slices = aggregateByCategory(
      expenses.map((e) => (category: e.category, amount: e.amount)),
    );

    // Dia mais caro.
    final priciest = dayTotals.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final df = DateFormat("d 'de' MMM", 'pt_BR');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      children: [
        // Período
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.mentaViva.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          child: Row(
            children: [
              Icon(AppIconsFill.calendarBlank, color: AppColors.verdeAguaProfundo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$periodDays ${periodDays == 1 ? 'dia' : 'dias'} de conta',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      '${df.format(minDate)} — ${df.format(maxDate)} · '
                      '$distinctDays ${distinctDays == 1 ? 'dia' : 'dias'} com despesa',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(child: _StatCard(label: 'Total da conta', value: total)),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(label: 'Sua parte', value: minhaParte, color: AppColors.verdeAguaProfundo)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _StatCard(label: 'Média por dia', value: avgPerDay, hint: 'dias com despesa')),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(label: 'Média por despesa', value: avgPerExpense, hint: '${expenses.length} despesas')),
          ],
        ),
        const SizedBox(height: 24),

        Text('Gasto por tipo', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        CategoryBars(slices: slices),

        const SizedBox(height: 12),
        // Destaques rápidos.
        _Highlight(
          icon: categoryHighlightIcon,
          text: 'Maior tipo: ',
          strong: slices.first.label,
          trailing: Money.format(slices.first.value),
        ),
        const SizedBox(height: 8),
        _Highlight(
          icon: AppIconsFill.arrowUp,
          text: 'Dia mais caro: ',
          strong: df.format(priciest.key),
          trailing: Money.format(priciest.value),
        ),
      ],
    );
  }
}

const IconData categoryHighlightIcon = Icons.local_fire_department_outlined;

class _StatCard extends StatelessWidget {
  final String label;
  final double value;
  final String? hint;
  final Color? color;
  const _StatCard({required this.label, required this.value, this.hint, this.color});

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
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          MoneyText(value, fontSize: 20, color: color),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  final IconData icon;
  final String text;
  final String strong;
  final String trailing;
  const _Highlight({required this.icon, required this.text, required this.strong, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.verdeAguaProfundo),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                TextSpan(text: text),
                TextSpan(text: strong, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        Text(trailing, style: AppTheme.moneyStyle(fontSize: 14)),
      ],
    );
  }
}
