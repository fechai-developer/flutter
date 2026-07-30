import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/balance.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/providers.dart';
import 'category_breakdown.dart';

/// Gasto de uma conta pela ótica do usuário (a "sua parte" na conta).
class GroupSpend {
  final String id;
  final String name;
  final String emoji;
  final double myShare;
  const GroupSpend({required this.id, required this.name, required this.emoji, required this.myShare});
}

/// Indicadores consolidados de TODAS as contas + assinaturas, na ótica do
/// usuário logado. Tudo derivado dos providers já cacheados (sem query nova).
class GlobalIndicators {
  final double toReceive;
  final double toPay;
  final double monthSpend; // sua parte das despesas do mês corrente
  final double subsMonthly; // soma das cotas que você paga por mês
  final int activeGroups;
  final int activeSubs;
  final List<CategorySlice> byCategory; // gasto por tipo (sua parte, todas as contas)
  final List<CategorySlice> subsByCategory; // compromisso mensal por tipo de assinatura
  final List<GroupSpend> topGroups; // contas ordenadas pela sua parte

  const GlobalIndicators({
    required this.toReceive,
    required this.toPay,
    required this.monthSpend,
    required this.subsMonthly,
    required this.activeGroups,
    required this.activeSubs,
    required this.byCategory,
    required this.subsByCategory,
    required this.topGroups,
  });

  double get net => toReceive - toPay;
  bool get isEmpty => byCategory.isEmpty && subsByCategory.isEmpty && toReceive == 0 && toPay == 0;
}

/// Data corrente do app. Isolada para facilitar futuros testes.
DateTime _today() => DateTime.now();

final globalIndicatorsProvider = FutureProvider<GlobalIndicators>((ref) async {
  final groups = await ref.watch(groupsProvider.future);
  final subs = await ref.watch(subscriptionsProvider.future);
  final now = _today();

  double toReceive = 0;
  double toPay = 0;
  double monthSpend = 0;
  var activeGroups = 0;

  final catItems = <({String? category, double amount})>[];
  final topGroups = <GroupSpend>[];

  for (final g in groups) {
    if (g.viewerRemoved) continue;
    activeGroups++;
    final net = BalanceCalculator.netBalances(g)['me'] ?? 0;
    if (net > 0) toReceive += net;
    if (net < 0) toPay += -net;

    double groupMine = 0;
    for (final e in g.expenses) {
      final mine = e.shares['me'] ?? 0;
      if (mine == 0) continue;
      groupMine += mine;
      catItems.add((category: e.category, amount: mine));
      if (e.date.year == now.year && e.date.month == now.month) {
        monthSpend += mine;
      }
    }
    if (groupMine > 0) {
      topGroups.add(GroupSpend(id: g.id, name: g.name, emoji: g.emoji, myShare: groupMine));
    }
  }

  double subsMonthly = 0;
  var activeSubs = 0;
  final subCatItems = <({String? category, double amount})>[];

  for (final s in subs) {
    if (s.viewerRemoved) continue;
    activeSubs++;
    // Cobranças em aberto que você tem a receber (dono) / a pagar (membro).
    if (s.ownerId == 'me') {
      toReceive += s.pendingThisCycle;
    } else {
      for (final m in s.members.where((m) => m.person.id == 'me' && !m.removed && m.status != QuotaStatus.paid)) {
        toPay += m.quota;
      }
    }
    // Compromisso mensal: a SUA cota (você também paga na assinatura que criou).
    final mine = s.members.where((m) => m.person.id == 'me' && !m.removed);
    for (final m in mine) {
      subsMonthly += m.quota;
      subCatItems.add((category: s.category, amount: m.quota));
    }
  }

  topGroups.sort((a, b) => b.myShare.compareTo(a.myShare));

  return GlobalIndicators(
    toReceive: double.parse(toReceive.toStringAsFixed(2)),
    toPay: double.parse(toPay.toStringAsFixed(2)),
    monthSpend: double.parse(monthSpend.toStringAsFixed(2)),
    subsMonthly: double.parse(subsMonthly.toStringAsFixed(2)),
    activeGroups: activeGroups,
    activeSubs: activeSubs,
    byCategory: aggregateByCategory(catItems),
    subsByCategory: aggregateByCategory(subCatItems),
    topGroups: topGroups,
  );
});
