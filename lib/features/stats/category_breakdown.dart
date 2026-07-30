import 'package:flutter/material.dart';

import '../../core/categories.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/money_text.dart';
import '../../theme/app_theme.dart';

/// Uma fatia de gasto por tipo (categoria), já agregada.
class CategorySlice {
  final String label; // rótulo do tipo (ou "Sem tipo")
  final double value; // total em R$
  final int count; // nº de itens
  const CategorySlice({required this.label, required this.value, this.count = 0});
}

/// Agrega uma lista de (categoria, valor) em fatias ordenadas por valor desc.
/// Itens sem categoria caem em [kNoCategoryLabel].
List<CategorySlice> aggregateByCategory(Iterable<({String? category, double amount})> items) {
  final totals = <String, double>{};
  final counts = <String, int>{};
  for (final it in items) {
    final key = (it.category == null || it.category!.trim().isEmpty)
        ? kNoCategoryLabel
        : it.category!.trim();
    totals[key] = (totals[key] ?? 0) + it.amount;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final slices = [
    for (final e in totals.entries)
      CategorySlice(label: e.key, value: e.value, count: counts[e.key] ?? 0),
  ]..sort((a, b) => b.value.compareTo(a.value));
  return slices;
}

/// Barras horizontais de gasto por tipo — ícone + rótulo + valor + %, com uma
/// barra proporcional ao maior. Cores estáveis da paleta de categorias.
class CategoryBars extends StatelessWidget {
  final List<CategorySlice> slices;
  final bool showCount;
  const CategoryBars({super.key, required this.slices, this.showCount = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (slices.isEmpty) return const SizedBox.shrink();
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    final maxVal = slices.first.value == 0 ? 1 : slices.first.value;

    return Column(
      children: [
        for (var i = 0; i < slices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _row(context, theme, slices[i], i, total, maxVal.toDouble()),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, ThemeData theme, CategorySlice s, int i, double total, double maxVal) {
    final color = categoryColor(i);
    final pct = total == 0 ? 0.0 : s.value / total * 100;
    final frac = (s.value / maxVal).clamp(0.02, 1.0);
    final avg = s.count == 0 ? 0.0 : s.value / s.count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(categoryIcon(s.label == kNoCategoryLabel ? null : s.label), size: 17, color: color),
            ),
            const SizedBox(width: 10),
            // Rótulo + linha suave "X itens · média R$ Y" (média por tipo).
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.label,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showCount)
                    Text(
                      '${s.count} ${s.count == 1 ? 'item' : 'itens'} · média ${Money.format(avg)}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MoneyText(s.value, fontSize: 14),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 7,
                  backgroundColor: AppColors.areiaNeutra,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 38,
              child: Text(
                '${pct.toStringAsFixed(0)}%',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
