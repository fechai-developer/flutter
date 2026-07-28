import 'package:uuid/uuid.dart';

import '../../core/utils/balance.dart';
import '../../core/utils/recurrence.dart';
import '../models/caixinha.dart';
import '../models/expense.dart';
import '../models/expense_group.dart';
import '../models/person.dart';
import '../models/plan_status.dart';
import '../models/subscription.dart';
import 'app_repository.dart';

/// Implementação em memória com dados de exemplo (seed) — permite ver toda a
/// UI/UX funcionando sem backend. Trocável por [SupabaseRepository] sem tocar
/// na camada de apresentação.
class InMemoryRepository implements AppRepository {
  final _uuid = const Uuid();

  late Person _me;
  final List<ExpenseGroup> _groups = [];
  final List<Subscription> _subscriptions = [];
  final List<Caixinha> _caixinhas = [];
  // Convites em aberto que EU recebi (grupos/assinaturas em que fui adicionado).
  final List<PendingInvite> _invites = [];

  InMemoryRepository() {
    _seed();
  }

  // Pequeno atraso simula latência de rede — deixa loaders visíveis na UI.
  Future<T> _delay<T>(T value) =>
      Future.delayed(const Duration(milliseconds: 220), () => value);

  void _seed() {
    _me = const Person(
      id: 'me',
      name: 'Você',
      phone: '5511988887777',
      pixKey: 'voce@email.com',
    );

    final ana = const Person(id: 'p_ana', name: 'Ana', lastName: 'Prado', phone: '5511911112222', pixKey: 'ana@email.com');
    final bruno = const Person(id: 'p_bruno', name: 'Bruno', lastName: 'Lima', phone: '5511933334444');
    final carla = const Person(id: 'p_carla', name: 'Carla', lastName: 'Souza', phone: '5511955556666');
    final diego = const Person(id: 'p_diego', name: 'Diego', lastName: 'Rocha', phone: '5511977778888');

    // Grupo de viagem com despesas. Carla foi convidada e ainda não aceitou —
    // aparece com o nome entre aspas + selo de pendente (Etapa C, itens 6/9).
    final viagem = ExpenseGroup(
      id: 'g_praia',
      name: 'Praia de Maresias',
      emoji: '🏖️',
      members: [_me, ana, bruno, carla],
      memberStatus: const {'p_carla': MemberStatus.pending},
      createdAt: DateTime(2026, 7, 5),
      expenses: [
        Expense.equalSplit(
          id: 'e1',
          description: 'Aluguel da casa',
          amount: 1200,
          paidByPersonId: 'me',
          participantIds: ['me', 'p_ana', 'p_bruno', 'p_carla'],
          date: DateTime(2026, 7, 6),
        ),
        Expense.equalSplit(
          id: 'e2',
          description: 'Mercado',
          amount: 480.50,
          paidByPersonId: 'p_ana',
          participantIds: ['me', 'p_ana', 'p_bruno', 'p_carla'],
          date: DateTime(2026, 7, 7),
        ),
        Expense.equalSplit(
          id: 'e3',
          description: 'Combustível',
          amount: 260,
          paidByPersonId: 'p_bruno',
          participantIds: ['me', 'p_bruno', 'p_carla'],
          date: DateTime(2026, 7, 7),
        ),
      ],
    );

    final rep = ExpenseGroup(
      id: 'g_rep',
      name: 'República',
      emoji: '🏠',
      members: [_me, carla, diego],
      createdAt: DateTime(2026, 7, 1),
      expenses: [
        Expense.equalSplit(
          id: 'e4',
          description: 'Conta de luz',
          amount: 189.90,
          paidByPersonId: 'me',
          participantIds: ['me', 'p_carla', 'p_diego'],
          date: DateTime(2026, 7, 10),
        ),
      ],
    );

    // Grupo em que EU fui convidado (dono é a Ana) e ainda não aceitei — gera
    // um convite na Home. Bruno recusou o convite deste grupo (item 6).
    final churras = ExpenseGroup(
      id: 'g_churras',
      name: 'Churrasco da Firma',
      emoji: '🍖',
      ownerId: 'p_ana',
      members: [ana, _me, bruno],
      memberStatus: const {'p_bruno': MemberStatus.declined},
      createdAt: DateTime(2026, 7, 18),
      expenses: const [],
    );

    // Grupo em que EU FUI REMOVIDO depois de ter participado (dono é a Ana).
    // Já acertei minha parte (saldo zerado), então continuo com acesso
    // SOMENTE ao histórico das despesas em que me envolvi — aparece
    // "Arquivado" na minha lista e abre em modo leitura.
    final arquivado = ExpenseGroup(
      id: 'g_arquivado',
      name: 'Rolê de Sábado',
      emoji: '🎉',
      ownerId: 'p_ana',
      members: [ana, _me, bruno],
      removedMemberIds: const {'me'},
      viewerRemoved: true,
      createdAt: DateTime(2026, 6, 20),
      expenses: [
        Expense.equalSplit(
          id: 'e_arq1',
          description: 'Uber do rolê',
          amount: 90,
          paidByPersonId: 'p_ana',
          participantIds: ['me', 'p_ana', 'p_bruno'],
          date: DateTime(2026, 6, 20),
        ),
      ],
      payments: [
        Payment(id: 'pay_arq1', fromId: 'me', toId: 'p_ana', amount: 30, date: DateTime(2026, 6, 21)),
      ],
    );

    // Grupo com DESPESA RECORRENTE onde um participante (Bruno) saiu já zerado.
    // A recorrência fica marcada para revisão (participantLeft): a próxima
    // ocorrência será redividida entre os ativos — badge de aviso no lançamento.
    final recorrente = ExpenseGroup(
      id: 'g_rec',
      name: 'Apê Compartilhado',
      emoji: '🏢',
      members: [_me, ana, bruno],
      removedMemberIds: const {'p_bruno'},
      createdAt: DateTime(2026, 6, 1),
      expenses: [
        Expense.create(
          id: 'e_rec1',
          description: 'Internet',
          amount: 90,
          paidByPersonId: 'me',
          type: SplitType.equal,
          participantIds: const ['me', 'p_ana', 'p_bruno'],
          date: DateTime(2026, 5, 1),
          recurrence: Recurrence.monthly,
          recurrenceDay: 1,
          recurrenceReview: RecurrenceReview.participantLeft,
        ),
      ],
      payments: [
        Payment(id: 'pay_rec1', fromId: 'p_bruno', toId: 'me', amount: 30, date: DateTime(2026, 5, 2)),
      ],
    );

    _groups.addAll([viagem, rep, churras, arquivado, recorrente]);

    _invites.addAll([
      const PendingInvite(kind: 'group', membershipId: 'g_churras', sourceId: 'g_churras', title: 'Churrasco da Firma', emoji: '🍖'),
      // Convite que recusei antes — continua listado para poder aceitar depois.
      const PendingInvite(
        kind: 'subscription',
        membershipId: 's_disney',
        sourceId: 's_disney',
        title: 'Disney+ da Vó',
        emoji: '🏰',
        status: MemberStatus.declined,
      ),
    ]);

    // Assinaturas compartilhadas
    _subscriptions.addAll([
      Subscription(
        id: 's_netflix',
        serviceName: 'Netflix',
        emoji: '🎬',
        totalAmount: 55.90,
        billingDay: 15,
        quotaCount: 4,
        monthlyInterestPct: 1.0,
        ownerId: 'me',
        members: [
          SubscriptionMember(person: _me, quota: 13.98, status: QuotaStatus.paid),
          SubscriptionMember(person: ana, quota: 13.98, status: QuotaStatus.paid),
          // Bruno foi convidado e ainda não aceitou — nome entre aspas + selo.
          SubscriptionMember(person: bruno, quota: 13.98, status: QuotaStatus.pending, inviteStatus: MemberStatus.pending),
          SubscriptionMember(person: carla, quota: 13.98, status: QuotaStatus.overdue, monthsLate: 1),
        ],
      ),
      Subscription(
        id: 's_spotify',
        serviceName: 'Spotify Família',
        emoji: '🎵',
        totalAmount: 34.90,
        billingDay: 5,
        quotaCount: 6,
        monthlyInterestPct: 0.0,
        ownerId: 'me',
        members: [
          SubscriptionMember(person: _me, quota: 5.82, status: QuotaStatus.paid),
          SubscriptionMember(person: diego, quota: 5.82, status: QuotaStatus.pending),
          SubscriptionMember(person: ana, quota: 5.82, status: QuotaStatus.paid),
        ],
      ),
    ]);

    // Caixinha de exemplo: você (dono/tesoureiro) + Ana (membro) e Bruno
    // (convidado, ainda não aceitou). Fernanda é tomadora EXTERNA (papel
    // borrower, sem aceite): pegou emprestado, já pagou uma parcela e o saldo
    // segue acumulando juros.
    final fernanda = const Person(id: 'p_fernanda', name: 'Fernanda', lastName: 'Alves', phone: '5511922223333');
    _caixinhas.add(Caixinha(
      id: 'cx_familia',
      name: 'Caixinha da Família',
      emoji: '🐷',
      ownerId: 'me',
      defaultInterestPct: 10,
      monthlyQuota: 200,
      createdAt: DateTime(2026, 5, 1),
      members: [
        CaixinhaMember(person: _me, role: CaixinhaRole.owner),
        CaixinhaMember(person: ana, role: CaixinhaRole.member),
        // Bruno foi convidado e ainda não aceitou (nome entre aspas + selo).
        CaixinhaMember(person: bruno, role: CaixinhaRole.member, inviteStatus: MemberStatus.pending),
        // Tomadora externa: sem aceite, não contribui, não entra na partilha.
        CaixinhaMember(person: fernanda, role: CaixinhaRole.borrower),
      ],
      contributions: [
        Contribution(id: 'ap1', personId: 'me', amount: 400, date: DateTime(2026, 5, 3)),
        Contribution(id: 'ap2', personId: 'p_ana', amount: 400, date: DateTime(2026, 5, 3)),
        Contribution(id: 'ap3', personId: 'me', amount: 200, date: DateTime(2026, 6, 3)),
        Contribution(id: 'ap4', personId: 'p_ana', amount: 200, date: DateTime(2026, 6, 3)),
      ],
      loans: [
        Loan(
          id: 'ln1',
          borrowerName: 'Fernanda',
          borrowerPersonId: 'p_fernanda',
          principal: 500,
          interestPct: 10,
          date: DateTime(2026, 6, 10),
          dueDate: DateTime(2026, 8, 10),
        ),
      ],
      earnings: [
        Earning(id: 'rd1', amount: 18.40, source: EarningSource.investment, date: DateTime(2026, 5, 31), note: 'Rendimento da poupança'),
        Earning(id: 'rd2', amount: 50, source: EarningSource.loanInterest, date: DateTime(2026, 6, 30), loanId: 'ln1'),
      ],
      loanPayments: [
        // Pagou R$ 200 dos R$ 550 devidos (500 principal + 50 juros); sobram 350.
        LoanPayment(id: 'lp1', loanId: 'ln1', amount: 200, date: DateTime(2026, 7, 5), note: 'Parcial'),
      ],
    ));

    // Caixinha da Ana onde EU sou tomador externo (papel borrower): abre na
    // visão restrita — só vejo o nome, meu empréstimo e o histórico.
    _caixinhas.add(Caixinha(
      id: 'cx_amigos',
      name: 'Amigos do Bairro',
      emoji: '🤝',
      ownerId: 'p_ana',
      defaultInterestPct: 8,
      monthlyQuota: 300,
      createdAt: DateTime(2026, 4, 1),
      members: [
        CaixinhaMember(person: ana, role: CaixinhaRole.owner),
        CaixinhaMember(person: carla, role: CaixinhaRole.member),
        CaixinhaMember(person: _me, role: CaixinhaRole.borrower),
      ],
      contributions: [
        Contribution(id: 'aa1', personId: 'p_ana', amount: 1000, date: DateTime(2026, 4, 2)),
        Contribution(id: 'aa2', personId: 'p_carla', amount: 1000, date: DateTime(2026, 4, 2)),
      ],
      loans: [
        Loan(id: 'ln2', borrowerName: 'Você', borrowerPersonId: 'me', principal: 800, interestPct: 8, date: DateTime(2026, 5, 12), dueDate: DateTime(2026, 9, 12)),
      ],
      earnings: [
        Earning(id: 'ee1', amount: 64, source: EarningSource.loanInterest, date: DateTime(2026, 6, 12), loanId: 'ln2'),
      ],
      loanPayments: [
        LoanPayment(id: 'lp2', loanId: 'ln2', amount: 300, date: DateTime(2026, 6, 20), note: '1ª parcela'),
      ],
    ));
  }

  @override
  Future<Person> currentUser() => _delay(_me);

  @override
  Future<PlanStatus> planStatus() => _delay(PlanStatus.free(
        activeGroups: _groups.length,
        activeSubscriptions: _subscriptions.length,
      ));

  @override
  Future<List<PendingInvite>> pendingInvites() => _delay(List.unmodifiable(_invites));

  @override
  Future<void> acceptInvite(PendingInvite invite) {
    // Aceitou → deixa de ser convite (o grupo/assinatura já está na lista).
    _invites.removeWhere((i) => i.membershipId == invite.membershipId && i.kind == invite.kind);
    return _delay(null);
  }

  @override
  Future<void> declineInvite(PendingInvite invite) {
    // Recusou → continua listado (agora como recusado) para poder aceitar depois.
    final idx = _invites.indexWhere((i) => i.membershipId == invite.membershipId && i.kind == invite.kind);
    if (idx >= 0) {
      final i = _invites[idx];
      _invites[idx] = PendingInvite(
        kind: i.kind,
        membershipId: i.membershipId,
        sourceId: i.sourceId,
        title: i.title,
        emoji: i.emoji,
        status: MemberStatus.declined,
      );
    }
    return _delay(null);
  }

  @override
  Future<void> updateProfile(Person user) {
    _me = user;
    return _delay(null);
  }

  @override
  Future<List<ExpenseGroup>> groups() => _delay(List.unmodifiable(_groups));

  @override
  Future<ExpenseGroup> groupById(String id) =>
      _delay(_groups.firstWhere((g) => g.id == id));

  @override
  Future<ExpenseGroup> createGroup({
    required String name,
    required String emoji,
    required List<Person> members,
    double monthlyInterestPct = 0,
  }) {
    final group = ExpenseGroup(
      id: _uuid.v4(),
      name: name,
      emoji: emoji,
      members: [_me, ...members.where((m) => m.id != _me.id)],
      expenses: const [],
      monthlyInterestPct: monthlyInterestPct,
      createdAt: DateTime(2026, 7, 20),
    );
    _groups.insert(0, group);
    return _delay(group);
  }

  @override
  Future<ExpenseGroup> addExpense(String groupId, Expense expense) {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    final updated = _groups[idx].copyWith(expenses: [expense, ..._groups[idx].expenses]);
    _groups[idx] = updated;
    return _delay(updated);
  }

  @override
  Future<ExpenseGroup> updateExpense(String groupId, Expense expense) {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    final expenses = _groups[idx]
        .expenses
        .map((e) => e.id == expense.id ? expense : e)
        .toList();
    final updated = _groups[idx].copyWith(expenses: expenses);
    _groups[idx] = updated;
    return _delay(updated);
  }

  @override
  Future<ExpenseGroup> deleteExpense(String groupId, String expenseId) {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    final expenses = _groups[idx].expenses.where((e) => e.id != expenseId).toList();
    final updated = _groups[idx].copyWith(expenses: expenses);
    _groups[idx] = updated;
    return _delay(updated);
  }

  @override
  Future<ExpenseGroup> addMember(String groupId, Person member) {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    final updated = _groups[idx].copyWith(members: [..._groups[idx].members, member]);
    _groups[idx] = updated;
    return _delay(updated);
  }

  @override
  Future<ExpenseGroup> removeMember(String groupId, String personId) {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    final g = _groups[idx];

    // Trava: só remove quem está zerado (sem saldo em aberto).
    final balance = BalanceCalculator.netBalances(g)[personId] ?? 0;
    if (balance.abs() > 0.01) {
      return Future.error(StateError('Saldo em aberto: acerte antes de remover.'));
    }

    // Já teve movimentação com a pessoa? (pagou / participou do rateio / acertou)
    final hasHistory = g.expenses.any((e) =>
            e.paidByPersonId == personId || e.shares.containsKey(personId)) ||
        g.payments.any((p) => p.fromId == personId || p.toId == personId);

    final ExpenseGroup updated;
    if (hasHistory) {
      // Soft: mantém a pessoa (histórico preservado), marca como removida.
      // Recorrências afetadas ganham flag de revisão: quem pagava saiu bloqueia
      // (payerLeft); participante do rateio saiu é só aviso (participantLeft).
      final expenses = g.expenses.map((e) {
        if (!e.isRecurring) return e;
        if (e.paidByPersonId == personId) {
          return e.copyWith(recurrenceReview: RecurrenceReview.payerLeft);
        }
        if (e.shares.containsKey(personId) && e.recurrenceReview == RecurrenceReview.none) {
          return e.copyWith(recurrenceReview: RecurrenceReview.participantLeft);
        }
        return e;
      }).toList();
      updated = g.copyWith(
        expenses: expenses,
        removedMemberIds: {...g.removedMemberIds, personId},
        viewerRemoved: personId == 'me' ? true : g.viewerRemoved,
      );
    } else {
      // Hard: some de vez.
      updated = g.copyWith(members: g.members.where((m) => m.id != personId).toList());
    }
    _groups[idx] = updated;
    return _delay(updated);
  }

  @override
  Future<ExpenseGroup> settleUp(String groupId, {required String fromId, required String toId, required double amount}) {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    final payment = Payment(
      id: _uuid.v4(),
      fromId: fromId,
      toId: toId,
      amount: amount,
      date: DateTime(2026, 7, 20),
    );
    final updated = _groups[idx].copyWith(payments: [..._groups[idx].payments, payment]);
    _groups[idx] = updated;
    return _delay(updated);
  }

  @override
  Future<String?> memberPixKey(String groupId, String personId) {
    final g = _groups.firstWhere((g) => g.id == groupId);
    return _delay(g.memberById(personId)?.pixKey);
  }

  @override
  Future<ExpenseGroup> updateGroup(String groupId, {String? name, String? emoji, double? monthlyInterestPct}) {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    final updated = _groups[idx].copyWith(name: name, emoji: emoji, monthlyInterestPct: monthlyInterestPct);
    _groups[idx] = updated;
    return _delay(updated);
  }

  @override
  Future<void> deleteGroup(String groupId) {
    _groups.removeWhere((g) => g.id == groupId);
    // Espelha o cascade do banco: some o grupo → convites daquele grupo se
    // invalidam (não é possível aceitar um convite de grupo já excluído).
    _invites.removeWhere((i) => i.kind == 'group' && i.sourceId == groupId);
    return _delay(null);
  }

  @override
  Future<ExpenseGroup> generateRecurrences(String groupId) {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    final g = _groups[idx];
    final novas = RecurrenceGenerator.due(g, DateTime.now());
    if (novas.isEmpty) return _delay(g);
    final updated = g.copyWith(expenses: [...novas, ...g.expenses]);
    _groups[idx] = updated;
    return _delay(updated);
  }

  @override
  Future<List<Subscription>> subscriptions() => _delay(List.unmodifiable(_subscriptions));

  @override
  Future<Subscription> subscriptionById(String id) =>
      _delay(_subscriptions.firstWhere((s) => s.id == id));

  @override
  Future<Subscription> createSubscription(Subscription subscription) {
    final withId = subscription.copyWith();
    final s = Subscription(
      id: _uuid.v4(),
      serviceName: withId.serviceName,
      emoji: withId.emoji,
      totalAmount: withId.totalAmount,
      billingDay: withId.billingDay,
      quotaCount: withId.quotaCount,
      monthlyInterestPct: withId.monthlyInterestPct,
      ownerId: _me.id,
      members: withId.members,
    );
    _subscriptions.insert(0, s);
    return _delay(s);
  }

  @override
  Future<Subscription> updateSubscription(
    String id, {
    String? serviceName,
    String? emoji,
    double? totalAmount,
    int? billingDay,
    int? quotaCount,
    double? monthlyInterestPct,
  }) {
    final idx = _subscriptions.indexWhere((s) => s.id == id);
    final updated = _subscriptions[idx].copyWith(
      serviceName: serviceName,
      emoji: emoji,
      totalAmount: totalAmount,
      billingDay: billingDay,
      quotaCount: quotaCount,
      monthlyInterestPct: monthlyInterestPct,
    );
    _subscriptions[idx] = updated;
    return _delay(updated);
  }

  @override
  Future<Subscription> setQuotaStatus(String subscriptionId, String personId, QuotaStatus status) {
    final idx = _subscriptions.indexWhere((s) => s.id == subscriptionId);
    final sub = _subscriptions[idx];
    final members = sub.members
        .map((m) => m.person.id == personId ? m.copyWith(status: status) : m)
        .toList();
    final updated = sub.copyWith(members: members);
    _subscriptions[idx] = updated;
    return _delay(updated);
  }

  @override
  Future<Subscription> addSubscriptionMember(String subscriptionId, SubscriptionMember member) {
    final idx = _subscriptions.indexWhere((s) => s.id == subscriptionId);
    final sub = _subscriptions[idx];
    final updated = sub.copyWith(members: [...sub.members, member]);
    _subscriptions[idx] = updated;
    return _delay(updated);
  }

  @override
  Future<Subscription> removeSubscriptionMember(String subscriptionId, String personId) {
    final idx = _subscriptions.indexWhere((s) => s.id == subscriptionId);
    final sub = _subscriptions[idx];
    final m = sub.members.firstWhere((m) => m.person.id == personId);

    // Trava: participante que aceitou precisa estar com a cota quitada.
    if (m.inviteAccepted && (m.status != QuotaStatus.paid || m.monthsLate > 0)) {
      return Future.error(StateError('Cota em aberto: quite antes de remover.'));
    }

    final Subscription updated;
    if (m.inviteAccepted) {
      // Soft: participou de fato (teve cota) → mantém o histórico.
      final members = sub.members
          .map((x) => x.person.id == personId ? x.copyWith(removed: true) : x)
          .toList();
      updated = sub.copyWith(
        members: members,
        viewerRemoved: personId == 'me' ? true : sub.viewerRemoved,
      );
    } else {
      // Hard: convite pendente/recusado → some (equivale a cancelar convite).
      updated = sub.copyWith(members: sub.members.where((x) => x.person.id != personId).toList());
    }
    _subscriptions[idx] = updated;
    return _delay(updated);
  }

  // ---- Caixinhas ----

  Future<Caixinha> _mutateCx(String id, Caixinha Function(Caixinha) fn) {
    final idx = _caixinhas.indexWhere((c) => c.id == id);
    final updated = fn(_caixinhas[idx]);
    _caixinhas[idx] = updated;
    return _delay(updated);
  }

  @override
  Future<List<Caixinha>> caixinhas() => _delay(List.unmodifiable(_caixinhas));

  @override
  Future<Caixinha> caixinhaById(String id) => _delay(_caixinhas.firstWhere((c) => c.id == id));

  @override
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
  }) {
    final now = DateTime.now();
    final invited = members.where((m) => m.id != _me.id).toList();
    // Aporte semente para quem tem saldo atual (caixinha em andamento).
    final seed = <Contribution>[
      for (final entry in openingBalances.entries)
        if (entry.value > 0)
          Contribution(id: _uuid.v4(), personId: entry.key, amount: entry.value, date: now),
    ];
    final cx = Caixinha(
      id: _uuid.v4(),
      name: name,
      emoji: emoji,
      ownerId: 'me',
      defaultInterestPct: defaultInterestPct,
      monthlyQuota: monthlyQuota,
      paymentDay: paymentDay,
      createdAt: now,
      startDate: startDate,
      endDate: endDate,
      members: [
        CaixinhaMember(person: _me, role: CaixinhaRole.owner, quotas: quotas['me'] ?? 1),
        for (final m in invited)
          CaixinhaMember(
            person: m,
            role: treasurers.contains(m.id) ? CaixinhaRole.treasurer : CaixinhaRole.member,
            inviteStatus: MemberStatus.pending,
            quotas: quotas[m.id] ?? 1,
          ),
      ],
      contributions: seed,
    );
    _caixinhas.insert(0, cx);
    return _delay(cx);
  }

  @override
  Future<Caixinha> updateCaixinha(String id, {String? name, String? emoji, double? defaultInterestPct, double? monthlyQuota, DateTime? startDate, DateTime? endDate, int? paymentDay}) =>
      _mutateCx(id, (c) => c.copyWith(name: name, emoji: emoji, defaultInterestPct: defaultInterestPct, monthlyQuota: monthlyQuota, startDate: startDate, endDate: endDate, paymentDay: paymentDay));

  @override
  Future<Caixinha> addContribution(String caixinhaId, {required String personId, required double amount, DateTime? date}) =>
      _mutateCx(caixinhaId, (c) => c.copyWith(contributions: [
            ...c.contributions,
            Contribution(id: _uuid.v4(), personId: personId, amount: amount, date: date ?? DateTime.now()),
          ]));

  @override
  Future<Caixinha> addEarning(String caixinhaId, {required double amount, required EarningSource source, String? loanId, String? note, DateTime? date}) =>
      _mutateCx(caixinhaId, (c) => c.copyWith(earnings: [
            ...c.earnings,
            Earning(id: _uuid.v4(), amount: amount, source: source, date: date ?? DateTime.now(), loanId: loanId, note: note),
          ]));

  @override
  Future<Caixinha> addLoan(String caixinhaId, {required Person borrower, required bool external, required double principal, required double interestPct, DateTime? dueDate, DateTime? date}) =>
      _mutateCx(caixinhaId, (c) {
        // Tomador externo que ainda não está na caixinha vira membro (papel
        // borrower, sem aceite). Interno já é membro contribuinte.
        final alreadyMember = c.members.any((m) => m.person.id == borrower.id);
        final members = (external && !alreadyMember)
            ? [...c.members, CaixinhaMember(person: borrower, role: CaixinhaRole.borrower)]
            : c.members;
        final loanDate = date ?? DateTime.now();
        final loanId = _uuid.v4();
        // Retroativo: juros cheios mês a mês até hoje.
        final retro = retroactiveLoanInterest(loanDate: loanDate, principal: principal, interestPct: interestPct, now: DateTime.now());
        return c.copyWith(
          members: members,
          loans: [
            ...c.loans,
            Loan(id: loanId, borrowerName: borrower.name, borrowerPersonId: borrower.id, principal: principal, interestPct: interestPct, date: loanDate, dueDate: dueDate),
          ],
          earnings: [
            ...c.earnings,
            for (final e in retro)
              Earning(id: _uuid.v4(), amount: e.amount, source: EarningSource.loanInterest, date: e.date, loanId: loanId, note: 'Juros de ${borrower.name}'),
          ],
        );
      });

  @override
  Future<Caixinha> updateLoan(String caixinhaId, String loanId, {double? principal, double? interestPct, DateTime? date, DateTime? dueDate}) =>
      _mutateCx(caixinhaId, (c) => c.copyWith(
            loans: c.loans.map((l) => l.id == loanId ? l.copyWith(principal: principal, interestPct: interestPct, date: date, dueDate: dueDate) : l).toList(),
          ));

  @override
  Future<Caixinha> recordLoanInterest(String caixinhaId, String loanId, double amount, {DateTime? date}) =>
      _mutateCx(caixinhaId, (c) {
        final loan = c.loans.firstWhere((l) => l.id == loanId);
        return c.copyWith(earnings: [
          ...c.earnings,
          Earning(
            id: _uuid.v4(),
            amount: amount,
            source: EarningSource.loanInterest,
            date: date ?? DateTime.now(),
            loanId: loanId,
            note: 'Juros de ${loan.borrowerName}',
          ),
        ]);
      });

  @override
  Future<Caixinha> addLoanPayment(String caixinhaId, String loanId, {required double amount, String? note, DateTime? date}) =>
      _mutateCx(caixinhaId, (c) => c.copyWith(loanPayments: [
            ...c.loanPayments,
            LoanPayment(id: _uuid.v4(), loanId: loanId, amount: amount, date: date ?? DateTime.now(), note: note),
          ]));

  @override
  Future<Caixinha> setTreasurer(String caixinhaId, String personId, bool isTreasurer) =>
      _mutateCx(caixinhaId, (c) => c.copyWith(
            // Só alterna entre membro e tesoureiro — dono e externo não mudam.
            members: c.members.map((m) {
              if (m.person.id != personId || m.role == CaixinhaRole.owner || m.role == CaixinhaRole.borrower) return m;
              return m.copyWith(role: isTreasurer ? CaixinhaRole.treasurer : CaixinhaRole.member);
            }).toList(),
          ));

  @override
  Future<Caixinha> setMemberQuotas(String caixinhaId, String personId, int quotas) =>
      _mutateCx(caixinhaId, (c) => c.copyWith(
            members: c.members.map((m) => m.person.id == personId ? m.copyWith(quotas: quotas) : m).toList(),
          ));

  @override
  Future<Caixinha> exitMember(String caixinhaId, String personId, {required double refund}) =>
      _mutateCx(caixinhaId, (c) => c.copyWith(exits: [
            ...c.exits,
            MemberExit(id: _uuid.v4(), memberId: personId, refund: refund, date: DateTime.now()),
          ]));

  @override
  Future<Caixinha> adjustBalance(String caixinhaId, String personId, {required double delta, String? note, DateTime? date}) =>
      _mutateCx(caixinhaId, (c) => c.copyWith(adjustments: [
            ...c.adjustments,
            Adjustment(id: _uuid.v4(), memberId: personId, delta: delta, note: note, date: date ?? DateTime.now()),
          ]));

  @override
  Future<Caixinha> addCaixinhaMember(String caixinhaId, Person member) =>
      _mutateCx(caixinhaId, (c) => c.copyWith(members: [
            ...c.members,
            CaixinhaMember(person: member, role: CaixinhaRole.member, inviteStatus: MemberStatus.pending),
          ]));

  @override
  Future<Caixinha> closeCaixinha(String caixinhaId) =>
      _mutateCx(caixinhaId, (c) => c.copyWith(status: CaixinhaStatus.closed, closedAt: DateTime.now()));

  @override
  Future<void> deleteCaixinha(String caixinhaId) {
    _caixinhas.removeWhere((c) => c.id == caixinhaId);
    return _delay(null);
  }
}
