import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/balance.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/providers.dart';

/// Ponto do gráfico: um mês com totais pago e recebido.
class MonthlyPoint {
  final String label; // "jul"
  final double received;
  final double paid;
  const MonthlyPoint({required this.label, required this.received, required this.paid});
}

/// Histórico mensal de pago x recebido (#13).
///
/// No MVP (mock) sintetiza 6 meses a partir do estado atual com fatores
/// determinísticos — quando o backend de dados entrar, isso passa a ler da
/// tabela `charges` (cobranças pagas por mês) + histórico de despesas.
final monthlyStatsProvider = FutureProvider<List<MonthlyPoint>>((ref) async {
  final groups = await ref.watch(groupsProvider.future);
  final subs = await ref.watch(subscriptionsProvider.future);

  double baseReceived = 0;
  double basePaid = 0;
  for (final g in groups) {
    final net = BalanceCalculator.netBalances(g)['me'] ?? 0;
    if (net > 0) baseReceived += net;
    if (net < 0) basePaid += -net;
  }
  for (final s in subs) {
    if (s.ownerId == 'me') {
      baseReceived += s.collectedThisCycle + s.pendingThisCycle;
    }
    for (final m in s.members.where((m) => m.person.id == 'me' && m.status == QuotaStatus.paid)) {
      basePaid += m.quota;
    }
  }
  // valores mínimos para o gráfico não ficar vazio
  if (baseReceived == 0) baseReceived = 120;
  if (basePaid == 0) basePaid = 80;

  const factorsR = [0.55, 0.7, 0.85, 0.75, 0.95, 1.0];
  const factorsP = [0.6, 0.8, 0.65, 0.9, 0.7, 1.0];
  final df = DateFormat('MMM', 'pt_BR');

  // Últimos 6 meses relativos a jul/2026 (data corrente do projeto).
  final base = DateTime(2026, 7, 1);
  final points = <MonthlyPoint>[];
  for (int i = 5; i >= 0; i--) {
    final month = DateTime(base.year, base.month - i, 1);
    final idx = 5 - i;
    points.add(MonthlyPoint(
      label: df.format(month).replaceAll('.', ''),
      received: double.parse((baseReceived * factorsR[idx]).toStringAsFixed(2)),
      paid: double.parse((basePaid * factorsP[idx]).toStringAsFixed(2)),
    ));
  }
  return points;
});
