import '../models/caixinha.dart';
import '../models/expense.dart';
import '../models/expense_group.dart';
import '../models/person.dart';
import '../models/plan_status.dart';
import '../models/subscription.dart';

/// Convite de aceite (#1/#3): grupo ou assinatura em que o usuário foi
/// adicionado. Enquanto não aceita, fica [MemberStatus.pending]; ao recusar,
/// vira [MemberStatus.declined] — mas continua listado para poder aceitar depois.
class PendingInvite {
  final String kind; // 'group' | 'subscription'
  final String membershipId; // linha em group_members / subscription_members
  final String? sourceId; // id do grupo/assinatura (para casar com a lista)
  final String title; // nome do grupo/serviço
  final String emoji;
  final MemberStatus status; // pending | declined
  const PendingInvite({
    required this.kind,
    required this.membershipId,
    this.sourceId,
    required this.title,
    required this.emoji,
    this.status = MemberStatus.pending,
  });

  bool get isDeclined => status == MemberStatus.declined;
}

/// Contrato da camada de dados. A UI depende só desta interface — a troca
/// entre mock in-memory (agora) e Supabase (backend real) é transparente.
abstract class AppRepository {
  /// Usuário logado (no MVP: cadastro por celular + OTP).
  Future<Person> currentUser();
  Future<void> updateProfile(Person user);

  /// Status do plano do usuário (freemium): limites, uso atual e se é premium.
  /// Usado para o gating comercial da UI (recursos premium desabilitados + upsell).
  Future<PlanStatus> planStatus();

  // ---- Convites (#1/#3, Etapa C) ----
  /// Convites em aberto: pendentes E recusados (recusado pode ser aceito depois).
  Future<List<PendingInvite>> pendingInvites();
  Future<void> acceptInvite(PendingInvite invite);
  Future<void> declineInvite(PendingInvite invite);

  // ---- Grupos de despesa ----
  Future<List<ExpenseGroup>> groups();
  Future<ExpenseGroup> groupById(String id);
  Future<ExpenseGroup> createGroup({required String name, required String emoji, required List<Person> members, double monthlyInterestPct});
  Future<ExpenseGroup> addExpense(String groupId, Expense expense);
  Future<ExpenseGroup> updateExpense(String groupId, Expense expense);
  Future<ExpenseGroup> deleteExpense(String groupId, String expenseId);
  Future<ExpenseGroup> addMember(String groupId, Person member);
  Future<ExpenseGroup> removeMember(String groupId, String personId);
  /// Registra um acerto: [fromId] pagou [amount] para [toId] (#4/#5).
  Future<ExpenseGroup> settleUp(String groupId, {required String fromId, required String toId, required double amount});
  /// Chave PIX de um membro do grupo, só se permitido (RLS/payee_info, #7). Null se indisponível.
  Future<String?> memberPixKey(String groupId, String personId);
  Future<ExpenseGroup> updateGroup(String groupId, {String? name, String? emoji, double? monthlyInterestPct});
  Future<void> deleteGroup(String groupId);
  /// Gera as ocorrências mensais vencidas das despesas recorrentes do grupo
  /// (exclui quem saiu, redivide proporcional; pula séries com pagador removido).
  /// Devolve o grupo atualizado. Idempotente.
  Future<ExpenseGroup> generateRecurrences(String groupId);

  // ---- Assinaturas compartilhadas ----
  Future<List<Subscription>> subscriptions();
  Future<Subscription> subscriptionById(String id);
  Future<Subscription> createSubscription(Subscription subscription);
  Future<Subscription> updateSubscription(
    String id, {
    String? serviceName,
    String? emoji,
    double? totalAmount,
    int? billingDay,
    int? quotaCount,
    double? monthlyInterestPct,
    String? category,
  });
  Future<Subscription> setQuotaStatus(String subscriptionId, String personId, QuotaStatus status);
  Future<Subscription> addSubscriptionMember(String subscriptionId, SubscriptionMember member);
  /// Remove um participante da assinatura. Só se estiver zerado. Se já teve
  /// vínculo aceito, mantém o histórico (soft); senão, some. Lança se em aberto.
  Future<Subscription> removeSubscriptionMember(String subscriptionId, String personId);

  // ---- Caixinhas (poupança coletiva + empréstimos a juros) ----
  Future<List<Caixinha>> caixinhas();
  Future<Caixinha> caixinhaById(String id);
  Future<Caixinha> createCaixinha({
    required String name,
    required String emoji,
    required double defaultInterestPct,
    required double monthlyQuota,
    required List<Person> members,
    Map<String, int> quotas,
    /// Caixinha em andamento: saldo atual de cada um (por person.id, 'me' p/ dono)
    /// — vira um aporte semente na abertura. Ausente/0 = não semeia.
    Map<String, double> openingBalances,
    /// person.ids que entram como tesoureiros (além do dono, sempre tesoureiro).
    Set<String> treasurers,
    DateTime? startDate,
    DateTime? endDate,
    /// Dia do mês em que a cota vence (aniversário mensal). Null = sem data.
    int? paymentDay,
  });
  Future<Caixinha> updateCaixinha(
    String id, {
    String? name,
    String? emoji,
    double? defaultInterestPct,
    double? monthlyQuota,
    DateTime? startDate,
    DateTime? endDate,
    int? paymentDay,
  });
  /// Lança um aporte: [personId] guardou [amount] na caixinha. [date] permite
  /// registrar num mês passado (default hoje); não pode ser antes da abertura.
  Future<Caixinha> addContribution(String caixinhaId, {required String personId, required double amount, DateTime? date});
  /// Lança um rendimento (investimento ou juros de empréstimo). [date] default hoje.
  Future<Caixinha> addEarning(
    String caixinhaId, {
    required double amount,
    required EarningSource source,
    String? loanId,
    String? note,
    DateTime? date,
  });
  /// Registra um empréstimo. [borrower] é a identidade do tomador; quando
  /// [external] é true (pessoa de fora), ela é cadastrada como membro de papel
  /// [CaixinhaRole.borrower] (sem aceite). Quando false, o tomador já é um
  /// membro contribuinte ("pra dentro").
  Future<Caixinha> addLoan(
    String caixinhaId, {
    required Person borrower,
    required bool external,
    required double principal,
    required double interestPct,
    DateTime? dueDate,
    DateTime? date,
  });
  /// Edita um empréstimo (valor/juros/data) — para reconciliar um lançamento do
  /// passado. Só tesoureiro/dono.
  Future<Caixinha> updateLoan(String caixinhaId, String loanId, {double? principal, double? interestPct, DateTime? date, DateTime? dueDate});
  /// Lança os juros do mês de um empréstimo (o valor é calculado pelo chamador
  /// a partir da taxa × saldo devedor) como rendimento da caixinha. [date] default hoje.
  Future<Caixinha> recordLoanInterest(String caixinhaId, String loanId, double amount, {DateTime? date});
  /// Registra um pagamento (parcial ou total) de um empréstimo. O saldo que
  /// sobrar continua acumulando juros. [date] default hoje.
  Future<Caixinha> addLoanPayment(String caixinhaId, String loanId, {required double amount, String? note, DateTime? date});
  /// Aplica uma quitação de cotas em atraso (plano montado por
  /// `Caixinha.planCotaSettlement`), em um passo só:
  /// - [contributions]: aportes retroativos, já datados no vencimento de cada mês;
  /// - [interestPaid]: juro efetivamente pago → vira rendimento da caixinha;
  /// - [chargePayments]: abatimentos em juros já cristalizados;
  /// - [newCharge]: juro que saiu do cálculo derivado sem ser pago → é
  ///   cristalizado para continuar devido (não some do radar).
  Future<Caixinha> settleCotaArrears(
    String caixinhaId, {
    required String personId,
    required List<({DateTime date, double amount})> contributions,
    required double interestPaid,
    required List<({String chargeId, double amount})> chargePayments,
    required double newCharge,
    DateTime? date,
  });
  /// Toggle de tesoureiro (só o dono pode eleger/remover).
  Future<Caixinha> setTreasurer(String caixinhaId, String personId, bool isTreasurer);
  /// Define quantas cotas um participante tem (multiplica o aporte sugerido).
  Future<Caixinha> setMemberQuotas(String caixinhaId, String personId, int quotas);
  /// Registra a saída de um participante: ele recebe de volta [refund] (só o que
  /// aportou, sem rendimento). Fica no histórico; o lucro dele vai para quem fica.
  Future<Caixinha> exitMember(String caixinhaId, String personId, {required double refund});
  /// Ajuste manual do saldo de um participante (só dono): aplica [delta] (com
  /// sinal) — muda o saldo da pessoa e o patrimônio. Fica no histórico.
  Future<Caixinha> adjustBalance(String caixinhaId, String personId, {required double delta, String? note, DateTime? date});
  Future<Caixinha> addCaixinhaMember(String caixinhaId, Person member);
  /// Encerra o período: a caixinha vai a [CaixinhaStatus.closed] e a partilha é
  /// exibida a partir da participação de cada um.
  Future<Caixinha> closeCaixinha(String caixinhaId);
  Future<void> deleteCaixinha(String caixinhaId);
}
