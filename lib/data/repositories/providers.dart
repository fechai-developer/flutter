import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_config.dart';
import '../../features/auth/auth_controller.dart';
import '../models/caixinha.dart';
import '../models/expense.dart';
import '../models/expense_group.dart';
import '../models/person.dart';
import '../models/plan_status.dart';
import '../models/subscription.dart';
import 'app_repository.dart';
import 'in_memory_repository.dart';
import 'supabase_repository.dart';

/// Fonte única do repositório de DADOS. Com o backend ativo (logado), usa o
/// Supabase real; senão, o mock in-memory (dev/offline). A UI não muda.
final appRepositoryProvider = Provider<AppRepository>((ref) {
  // Reage só à IDENTIDADE do usuário (login/logout/troca de conta), NÃO ao
  // objeto Session inteiro. O Supabase renova o token periodicamente e ao voltar
  // o foco; sem o `.select`, cada renovação recriava o repositório e TODA a
  // leitura recarregava do zero (a tela piscava em branco a cada alt-tab).
  ref.watch(sessionProvider.select((s) => s?.user.id));
  if (SupabaseConfig.backendActive && Supabase.instance.client.auth.currentUser != null) {
    return SupabaseRepository();
  }
  return InMemoryRepository();
});

/// Usuário logado (perfil real quando no Supabase; mock caso contrário).
final currentUserProvider = FutureProvider<Person>((ref) {
  return ref.watch(appRepositoryProvider).currentUser();
});

/// Convites pendentes de aceite (#1).
final pendingInvitesProvider = FutureProvider<List<PendingInvite>>((ref) {
  return ref.watch(appRepositoryProvider).pendingInvites();
});

/// Status do plano (freemium) do usuário — gating comercial da UI.
final planStatusProvider = FutureProvider<PlanStatus>((ref) {
  return ref.watch(appRepositoryProvider).planStatus();
});

/// Lista de grupos de despesa. `autoDispose` não usado de propósito — mantém
/// cache entre navegações. Invalidar após mutações.
final groupsProvider = FutureProvider<List<ExpenseGroup>>((ref) {
  return ref.watch(appRepositoryProvider).groups();
});

final groupByIdProvider = FutureProvider.family<ExpenseGroup, String>((ref, id) {
  // depende de groupsProvider para reagir a invalidações
  ref.watch(groupsProvider);
  return ref.watch(appRepositoryProvider).groupById(id);
});

/// Lista de assinaturas compartilhadas.
final subscriptionsProvider = FutureProvider<List<Subscription>>((ref) {
  return ref.watch(appRepositoryProvider).subscriptions();
});

final subscriptionByIdProvider = FutureProvider.family<Subscription, String>((ref, id) {
  ref.watch(subscriptionsProvider);
  return ref.watch(appRepositoryProvider).subscriptionById(id);
});

/// Lista de caixinhas (poupança coletiva). Invalidar após mutações.
final caixinhasProvider = FutureProvider<List<Caixinha>>((ref) {
  return ref.watch(appRepositoryProvider).caixinhas();
});

final caixinhaByIdProvider = FutureProvider.family<Caixinha, String>((ref, id) {
  ref.watch(caixinhasProvider); // reage a invalidações da lista
  return ref.watch(appRepositoryProvider).caixinhaById(id);
});

/// Controller com as mutações; invalida os providers de leitura após cada uma.
class RepositoryController {
  final Ref ref;
  RepositoryController(this.ref);

  AppRepository get _repo => ref.read(appRepositoryProvider);

  Future<ExpenseGroup> createGroup({
    required String name,
    required String emoji,
    required List<Person> members,
    double monthlyInterestPct = 0,
  }) async {
    final g = await _repo.createGroup(
        name: name, emoji: emoji, members: members, monthlyInterestPct: monthlyInterestPct);
    ref.invalidate(groupsProvider);
    ref.invalidate(planStatusProvider);
    return g;
  }

  Future<void> addExpense(String groupId, Expense expense) async {
    await _repo.addExpense(groupId, expense);
    ref.invalidate(groupsProvider);
  }

  Future<void> updateExpense(String groupId, Expense expense) async {
    await _repo.updateExpense(groupId, expense);
    ref.invalidate(groupsProvider);
  }

  Future<void> deleteExpense(String groupId, String expenseId) async {
    await _repo.deleteExpense(groupId, expenseId);
    ref.invalidate(groupsProvider);
  }

  Future<void> addMember(String groupId, Person member) async {
    await _repo.addMember(groupId, member);
    ref.invalidate(groupsProvider);
  }

  Future<void> removeMember(String groupId, String personId) async {
    await _repo.removeMember(groupId, personId);
    ref.invalidate(groupsProvider);
  }

  Future<void> settleUp(String groupId, {required String fromId, required String toId, required double amount}) async {
    await _repo.settleUp(groupId, fromId: fromId, toId: toId, amount: amount);
    ref.invalidate(groupsProvider);
  }

  Future<String?> memberPixKey(String groupId, String personId) =>
      _repo.memberPixKey(groupId, personId);

  Future<void> updateGroup(String groupId, {String? name, String? emoji, double? monthlyInterestPct}) async {
    await _repo.updateGroup(groupId, name: name, emoji: emoji, monthlyInterestPct: monthlyInterestPct);
    ref.invalidate(groupsProvider);
  }

  Future<void> deleteGroup(String groupId) async {
    await _repo.deleteGroup(groupId);
    ref.invalidate(groupsProvider);
    ref.invalidate(planStatusProvider);
  }

  Future<int> generateRecurrences(String groupId) async {
    final before = (await _repo.groupById(groupId)).expenses.length;
    final g = await _repo.generateRecurrences(groupId);
    ref.invalidate(groupsProvider);
    return g.expenses.length - before;
  }

  Future<Subscription> createSubscription(Subscription subscription) async {
    final s = await _repo.createSubscription(subscription);
    ref.invalidate(subscriptionsProvider);
    ref.invalidate(planStatusProvider);
    return s;
  }

  Future<void> setQuotaStatus(String subscriptionId, String personId, QuotaStatus status) async {
    await _repo.setQuotaStatus(subscriptionId, personId, status);
    ref.invalidate(subscriptionsProvider);
  }

  Future<void> updateSubscription(
    String id, {
    String? serviceName,
    String? emoji,
    double? totalAmount,
    int? billingDay,
    int? quotaCount,
    double? monthlyInterestPct,
    String? category,
  }) async {
    await _repo.updateSubscription(
      id,
      serviceName: serviceName,
      emoji: emoji,
      totalAmount: totalAmount,
      billingDay: billingDay,
      quotaCount: quotaCount,
      monthlyInterestPct: monthlyInterestPct,
      category: category,
    );
    ref.invalidate(subscriptionsProvider);
  }

  Future<void> addSubscriptionMember(String subscriptionId, SubscriptionMember member) async {
    await _repo.addSubscriptionMember(subscriptionId, member);
    ref.invalidate(subscriptionsProvider);
  }

  Future<void> removeSubscriptionMember(String subscriptionId, String personId) async {
    await _repo.removeSubscriptionMember(subscriptionId, personId);
    ref.invalidate(subscriptionsProvider);
  }

  Future<void> updateProfile(Person user) async {
    await _repo.updateProfile(user);
    ref.invalidate(currentUserProvider);
  }

  // ---- Caixinhas ----

  Future<Caixinha> createCaixinha({
    required String name,
    required String emoji,
    required double defaultInterestPct,
    required double monthlyQuota,
    required List<Person> members,
    Map<String, int> quotas = const {},
    Map<String, double> openingBalances = const {},
    Set<String> treasurers = const {},
    DateTime? startDate,
    DateTime? endDate,
    int? paymentDay,
  }) async {
    final c = await _repo.createCaixinha(
      name: name,
      emoji: emoji,
      defaultInterestPct: defaultInterestPct,
      monthlyQuota: monthlyQuota,
      members: members,
      quotas: quotas,
      openingBalances: openingBalances,
      treasurers: treasurers,
      startDate: startDate,
      endDate: endDate,
      paymentDay: paymentDay,
    );
    ref.invalidate(caixinhasProvider);
    ref.invalidate(planStatusProvider);
    return c;
  }

  Future<void> updateCaixinha(String id, {String? name, String? emoji, double? defaultInterestPct, double? monthlyQuota, DateTime? startDate, DateTime? endDate, int? paymentDay}) async {
    await _repo.updateCaixinha(id, name: name, emoji: emoji, defaultInterestPct: defaultInterestPct, monthlyQuota: monthlyQuota, startDate: startDate, endDate: endDate, paymentDay: paymentDay);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> addContribution(String caixinhaId, {required String personId, required double amount, DateTime? date}) async {
    await _repo.addContribution(caixinhaId, personId: personId, amount: amount, date: date);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> addEarning(String caixinhaId, {required double amount, required EarningSource source, String? loanId, String? note, DateTime? date}) async {
    await _repo.addEarning(caixinhaId, amount: amount, source: source, loanId: loanId, note: note, date: date);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> addLoan(String caixinhaId, {required Person borrower, required bool external, required double principal, required double interestPct, DateTime? dueDate, DateTime? date}) async {
    await _repo.addLoan(caixinhaId, borrower: borrower, external: external, principal: principal, interestPct: interestPct, dueDate: dueDate, date: date);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> updateLoan(String caixinhaId, String loanId, {double? principal, double? interestPct, DateTime? date, DateTime? dueDate}) async {
    await _repo.updateLoan(caixinhaId, loanId, principal: principal, interestPct: interestPct, date: date, dueDate: dueDate);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> recordLoanInterest(String caixinhaId, String loanId, double amount, {DateTime? date}) async {
    await _repo.recordLoanInterest(caixinhaId, loanId, amount, date: date);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> addLoanPayment(String caixinhaId, String loanId, {required double amount, String? note, DateTime? date}) async {
    await _repo.addLoanPayment(caixinhaId, loanId, amount: amount, note: note, date: date);
    ref.invalidate(caixinhasProvider);
  }

  /// Aplica o plano de quitação de cotas em atraso (ver `Caixinha.planCotaSettlement`).
  Future<void> settleCotaArrears(
    String caixinhaId, {
    required String personId,
    required List<({DateTime date, double amount})> contributions,
    required double interestPaid,
    required List<({String chargeId, double amount})> chargePayments,
    required double newCharge,
    DateTime? date,
  }) async {
    await _repo.settleCotaArrears(
      caixinhaId,
      personId: personId,
      contributions: contributions,
      interestPaid: interestPaid,
      chargePayments: chargePayments,
      newCharge: newCharge,
      date: date,
    );
    ref.invalidate(caixinhasProvider);
  }

  Future<void> setTreasurer(String caixinhaId, String personId, bool isTreasurer) async {
    await _repo.setTreasurer(caixinhaId, personId, isTreasurer);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> setMemberQuotas(String caixinhaId, String personId, int quotas) async {
    await _repo.setMemberQuotas(caixinhaId, personId, quotas);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> exitMember(String caixinhaId, String personId, {required double refund}) async {
    await _repo.exitMember(caixinhaId, personId, refund: refund);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> adjustBalance(String caixinhaId, String personId, {required double delta, String? note, DateTime? date}) async {
    await _repo.adjustBalance(caixinhaId, personId, delta: delta, note: note, date: date);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> addCaixinhaMember(String caixinhaId, Person member) async {
    await _repo.addCaixinhaMember(caixinhaId, member);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> closeCaixinha(String caixinhaId) async {
    await _repo.closeCaixinha(caixinhaId);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> deleteCaixinha(String caixinhaId) async {
    await _repo.deleteCaixinha(caixinhaId);
    ref.invalidate(caixinhasProvider);
    ref.invalidate(planStatusProvider);
  }

  Future<void> acceptInvite(PendingInvite invite) async {
    await _repo.acceptInvite(invite);
    ref.invalidate(pendingInvitesProvider);
    ref.invalidate(groupsProvider);
    ref.invalidate(subscriptionsProvider);
    ref.invalidate(caixinhasProvider);
  }

  Future<void> declineInvite(PendingInvite invite) async {
    await _repo.declineInvite(invite);
    ref.invalidate(pendingInvitesProvider);
    ref.invalidate(groupsProvider);
    ref.invalidate(subscriptionsProvider);
    ref.invalidate(caixinhasProvider);
  }
}

final repositoryControllerProvider = Provider<RepositoryController>((ref) {
  return RepositoryController(ref);
});

/// Tipos (categorias) que o usuário já usou nas despesas das contas ATIVAS —
/// alimenta a "gaveta" de personalizadas no seletor de tipo. Ordenado A→Z.
final usedExpenseCategoriesProvider = Provider<List<String>>((ref) {
  final groups = ref.watch(groupsProvider).valueOrNull ?? const [];
  final set = <String>{};
  for (final g in groups) {
    if (g.viewerRemoved) continue;
    for (final e in g.expenses) {
      final c = e.category?.trim();
      if (c != null && c.isNotEmpty) set.add(c);
    }
  }
  return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
});

/// Idem para assinaturas ativas.
final usedSubscriptionCategoriesProvider = Provider<List<String>>((ref) {
  final subs = ref.watch(subscriptionsProvider).valueOrNull ?? const [];
  final set = <String>{};
  for (final s in subs) {
    if (s.viewerRemoved) continue;
    final c = s.category?.trim();
    if (c != null && c.isNotEmpty) set.add(c);
  }
  return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
});
