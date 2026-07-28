import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/money_text.dart';
import '../../theme/app_theme.dart';
import 'monthly_stats.dart';

/// Tela de resumo com gráfico de barras pago x recebido por mês (#13).
class MonthlyChartScreen extends ConsumerWidget {
  const MonthlyChartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(monthlyStatsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Resumo'),
      ),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (points) {
          final totalReceived = points.fold<double>(0, (a, p) => a + p.received);
          final totalPaid = points.fold<double>(0, (a, p) => a + p.paid);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Row(
                children: [
                  Expanded(child: _TotalCard(label: 'Recebido (6 meses)', value: totalReceived, color: AppColors.verdeAguaProfundo)),
                  const SizedBox(width: 12),
                  Expanded(child: _TotalCard(label: 'Pago (6 meses)', value: totalPaid, color: AppColors.coralAceso)),
                ],
              ),
              const SizedBox(height: 24),
              Text('Por mês', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Row(
                children: [
                  _LegendDot(color: AppColors.mentaViva, label: 'Recebido'),
                  const SizedBox(width: 16),
                  _LegendDot(color: AppColors.coralAceso, label: 'Pago'),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  border: Border.all(color: AppColors.areiaNeutra),
                ),
                child: _BarChart(points: points),
              ),
              const SizedBox(height: 20),
              Text(
                'Valores dos últimos 6 meses. Quando a cobrança automática estiver ligada, '
                'o gráfico passa a refletir os pagamentos realmente registrados.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<MonthlyPoint> points;
  const _BarChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxVal = points.fold<double>(
      1,
      (m, p) => [m, p.received, p.paid].reduce((a, b) => a > b ? a : b),
    );

    return SizedBox(
      height: 200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final p in points)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Bar(value: p.received, maxVal: maxVal, color: AppColors.mentaViva),
                        const SizedBox(width: 4),
                        _Bar(value: p.paid, maxVal: maxVal, color: AppColors.coralAceso),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(p.label, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final double maxVal;
  final Color color;
  const _Bar({required this.value, required this.maxVal, required this.color});

  @override
  Widget build(BuildContext context) {
    final frac = (value / maxVal).clamp(0.02, 1.0);
    return Tooltip(
      message: Money.format(value),
      child: FractionallySizedBox(
        heightFactor: frac,
        child: Container(
          width: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _TotalCard({required this.label, required this.value, required this.color});

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
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
