import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/wave_card.dart';
import '../../theme/app_theme.dart';
import 'category_breakdown.dart';
import 'indicators.dart';
import 'monthly_stats.dart';

/// Página dedicada de Indicadores (item 6): visão consolidada de todas as contas
/// e assinaturas, pensada pra responder "onde meu dinheiro foi" num relance.
class IndicatorsScreen extends ConsumerWidget {
  const IndicatorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(globalIndicatorsProvider);
    // Em tela larga o Resumo é item fixo da sidebar (não precisa de "voltar").
    // No celular ele saiu da barra de baixo e se chega por um botão na Home —
    // então aqui é uma tela de leitura, com o caminho de volta explícito.
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: wide
            ? null
            : IconButton(
                icon: Icon(AppIcons.arrowLeft),
                tooltip: 'Voltar',
                onPressed: () => context.go('/home'),
              ),
        title: const Text('Indicadores'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (ind) {
          if (ind.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.chartBar, size: 56, color: AppColors.mentaViva),
                  const SizedBox(height: 12),
                  Text('Sem dados ainda', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Crie contas e assinaturas pra ver seus indicadores.', style: theme.textTheme.bodySmall),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _Hero(ind: ind),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _Kpi(label: 'Gasto do mês', value: ind.monthSpend, hint: 'sua parte', color: AppColors.verdeAguaProfundo)),
                  const SizedBox(width: 12),
                  Expanded(child: _Kpi(label: 'Assinaturas / mês', value: ind.subsMonthly, hint: '${ind.activeSubs} ativas')),
                ],
              ),
              const SizedBox(height: 28),

              if (ind.byCategory.isNotEmpty) ...[
                Text('Onde seu dinheiro foi', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text('Sua parte somada em todas as contas', style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                CategoryBars(slices: ind.byCategory),
                const SizedBox(height: 24),
              ],

              if (ind.topGroups.isNotEmpty) ...[
                Text('Contas por gasto', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                _TopGroups(groups: ind.topGroups),
                const SizedBox(height: 24),
              ],

              if (ind.subsByCategory.isNotEmpty) ...[
                Text('Assinaturas por tipo', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text('Sua cota mensal por categoria', style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                CategoryBars(slices: ind.subsByCategory),
                const SizedBox(height: 24),
              ],

              const _MonthlyTrend(),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final GlobalIndicators ind;
  const _Hero({required this.ind});

  @override
  Widget build(BuildContext context) {
    final net = ind.net;
    return WaveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            net >= 0 ? 'Você tem a receber' : 'Você deve no total',
            style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(Money.format(net.abs()), style: AppTheme.moneyStyle(fontSize: 40, color: Colors.white)),
          const SizedBox(height: 20),
          Row(
            children: [
              _HeroStat(label: 'A receber', value: ind.toReceive, icon: AppIconsFill.arrowDown),
              const SizedBox(width: 24),
              _HeroStat(label: 'A pagar', value: ind.toPay, icon: AppIconsFill.arrowUp),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  const _HeroStat({required this.label, required this.value, required this.icon});

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
            Text(Money.format(value), style: AppTheme.moneyStyle(fontSize: 15, color: Colors.white)),
          ],
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final double value;
  final String? hint;
  final Color? color;
  const _Kpi({required this.label, required this.value, this.hint, this.color});

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

class _TopGroups extends StatelessWidget {
  final List<GroupSpend> groups;
  const _TopGroups({required this.groups});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxVal = groups.first.myShare == 0 ? 1.0 : groups.first.myShare;
    return Column(
      children: [
        for (final g in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.go('/groups/${g.id}'),
              child: Row(
                children: [
                  Text(g.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: (g.myShare / maxVal).clamp(0.02, 1.0),
                            minHeight: 7,
                            backgroundColor: AppColors.areiaNeutra,
                            valueColor: const AlwaysStoppedAnimation(AppColors.verdeAguaProfundo),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  MoneyText(g.myShare, fontSize: 14),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Tendência mensal de pago x recebido — reaproveita [monthlyStatsProvider].
class _MonthlyTrend extends ConsumerWidget {
  const _MonthlyTrend();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(monthlyStatsProvider).valueOrNull;
    if (stats == null || stats.isEmpty) return const SizedBox.shrink();
    final maxVal = stats.fold<double>(1, (m, p) => [m, p.received, p.paid].reduce((a, b) => a > b ? a : b));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pago x recebido', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Row(
          children: [
            _dot(context, AppColors.mentaViva, 'Recebido'),
            const SizedBox(width: 16),
            _dot(context, AppColors.coralAceso, 'Pago'),
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
          child: SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final p in stats)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _bar(p.received, maxVal, AppColors.mentaViva),
                              const SizedBox(width: 4),
                              _bar(p.paid, maxVal, AppColors.coralAceso),
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
          ),
        ),
      ],
    );
  }

  Widget _bar(double value, double maxVal, Color color) {
    final frac = (value / maxVal).clamp(0.02, 1.0);
    return Tooltip(
      message: Money.format(value),
      child: FractionallySizedBox(
        heightFactor: frac,
        child: Container(
          width: 14,
          decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
        ),
      ),
    );
  }

  Widget _dot(BuildContext context, Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
