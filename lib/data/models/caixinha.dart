import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'person.dart';

/// Situação da caixinha: aberta (recebendo aportes/rendimentos) ou encerrada
/// (partilhada entre os membros).
enum CaixinhaStatus { open, closed }

/// Origem de um rendimento lançado no mês.
/// - [investment]: rendimento do dinheiro parado (banco/investimento).
/// - [loanInterest]: juros acumulados de um empréstimo.
enum EarningSource { investment, loanInterest }

/// Papel de um participante na caixinha.
/// - [owner]: criador. Vê e edita tudo; elege tesoureiros; encerra.
/// - [treasurer]: eleito pelo dono. Vê e edita (lança aporte/rendimento/empréstimo).
/// - [member]: contribui e acompanha; não lança pelos outros.
/// - [borrower]: pessoa de fora que só pegou empréstimo. Não contribui e não
///   participa da partilha; visão restrita (o que pegou, o que deve, histórico).
///   Não tem fluxo de aceite — é cadastrada direto pelo tesoureiro.
enum CaixinhaRole { owner, treasurer, member, borrower }

/// Participante de uma caixinha (membro contribuinte ou tomador externo).
@immutable
class CaixinhaMember {
  final Person person;
  final CaixinhaRole role;
  final MemberStatus inviteStatus;

  /// Quantas cotas o participante tem (padrão 1). Multiplica o aporte mensal
  /// sugerido (nº de cotas × valor da cota). Não se aplica a tomadores externos.
  final int quotas;

  const CaixinhaMember({
    required this.person,
    this.role = CaixinhaRole.member,
    this.inviteStatus = MemberStatus.accepted,
    this.quotas = 1,
  });

  bool get isOwner => role == CaixinhaRole.owner;

  /// Quem pode lançar movimentação: dono e tesoureiros.
  bool get isTreasurer => role == CaixinhaRole.owner || role == CaixinhaRole.treasurer;

  /// Tomador externo (só pegou empréstimo).
  bool get isBorrower => role == CaixinhaRole.borrower;

  /// Participa da poupança (aporta e entra na partilha). Externos, não.
  bool get contributes => role != CaixinhaRole.borrower;

  bool get inviteAccepted => inviteStatus == MemberStatus.accepted;
  bool get invitePending => inviteStatus == MemberStatus.pending;
  bool get inviteDeclined => inviteStatus == MemberStatus.declined;

  CaixinhaMember copyWith({CaixinhaRole? role, MemberStatus? inviteStatus, int? quotas}) => CaixinhaMember(
        person: person,
        role: role ?? this.role,
        inviteStatus: inviteStatus ?? this.inviteStatus,
        quotas: quotas ?? this.quotas,
      );
}

/// Saída de um participante: ele recebe de volta **só o que aportou** (sem
/// rendimento). O lucro que teria fica na caixinha, redistribuído entre quem
/// permanece. Registrado no histórico ("saiu e recebeu R$ X").
@immutable
class MemberExit {
  final String id;
  final String memberId; // personId ('me' ou id da linha)
  final double refund;
  final DateTime date;
  final String? recordedBy; // personId de quem registrou

  const MemberExit({required this.id, required this.memberId, required this.refund, required this.date, this.recordedBy});
}

/// Ajuste manual do saldo de um participante feito pelo dono (correção). [delta]
/// é a diferença aplicada (positiva ou negativa) — muda o saldo da pessoa e o
/// patrimônio total no mesmo valor. Aparece no histórico como "Ajuste manual".
@immutable
class Adjustment {
  final String id;
  final String memberId;
  final double delta;
  final String? note;
  final DateTime date;
  final String? recordedBy; // personId de quem registrou

  const Adjustment({required this.id, required this.memberId, required this.delta, this.note, required this.date, this.recordedBy});
}

/// Tipo de movimentação no histórico (extrato) da caixinha.
enum MovementKind { contribution, earning, adjustment, exit }

/// Uma linha do histórico: a movimentação + o patrimônio resultante depois dela.
@immutable
class CaixinhaMovement {
  final DateTime date;
  final MovementKind kind;
  final String label;
  final double amount; // efeito (com sinal) no patrimônio
  final double balanceAfter; // patrimônio depois desta movimentação

  /// Nome (completo) de quem REGISTROU a movimentação, quando conhecido e
  /// diferente da pessoa a que ela se refere. Null quando não há autoria
  /// registrada (lançamentos antigos) ou quando o autor é a própria pessoa.
  final String? recordedByName;

  const CaixinhaMovement({
    required this.date,
    required this.kind,
    required this.label,
    required this.amount,
    required this.balanceAfter,
    this.recordedByName,
  });
}

/// Aporte: um membro guardou [amount] na caixinha em [date]. Cada aporte
/// "compra" unidades de participação pelo valor da unidade naquele momento.
@immutable
class Contribution {
  final String id;
  final String personId;
  final double amount;
  final DateTime date;
  final String? recordedBy; // personId de quem registrou

  const Contribution({
    required this.id,
    required this.personId,
    required this.amount,
    required this.date,
    this.recordedBy,
  });
}

/// Rendimento lançado num mês: do investimento (banco) ou de juros de
/// empréstimo. Sobe o patrimônio — e, portanto, o valor da unidade —
/// distribuindo o ganho por quem já tinha dinheiro na caixinha.
@immutable
class Earning {
  final String id;
  final double amount;
  final EarningSource source;
  final DateTime date;
  final String? loanId; // preenchido quando [source] == loanInterest
  final String? note;
  final String? recordedBy; // personId de quem registrou

  const Earning({
    required this.id,
    required this.amount,
    required this.source,
    required this.date,
    this.loanId,
    this.note,
    this.recordedBy,
  });

  bool get fromLoan => source == EarningSource.loanInterest;
}

/// Pagamento (total ou parcial) de um empréstimo. O histórico fica visível para
/// o tomador. Reduz o saldo devedor; o que sobrar segue acumulando juros.
@immutable
class LoanPayment {
  final String id;
  final String loanId;
  final double amount;
  final DateTime date;
  final String? note;

  const LoanPayment({
    required this.id,
    required this.loanId,
    required this.amount,
    required this.date,
    this.note,
  });
}

/// Empréstimo concedido pela caixinha. O tomador é sempre um membro cadastrado:
/// um contribuinte ("pra dentro") ou uma pessoa externa com papel
/// [CaixinhaRole.borrower] ("pra fora"). O dinheiro sai do caixa mas continua no
/// patrimônio como "a receber".
@immutable
class Loan {
  final String id;
  final String borrowerName;
  final String borrowerPersonId;
  final double principal;
  final double interestPct; // ao mês
  final DateTime date;
  final DateTime? dueDate;

  const Loan({
    required this.id,
    required this.borrowerName,
    required this.borrowerPersonId,
    required this.principal,
    required this.interestPct,
    required this.date,
    this.dueDate,
  });

  Loan copyWith({String? borrowerName, double? principal, double? interestPct, DateTime? date, Object? dueDate = _unset}) => Loan(
        id: id,
        borrowerName: borrowerName ?? this.borrowerName,
        borrowerPersonId: borrowerPersonId,
        principal: principal ?? this.principal,
        interestPct: interestPct ?? this.interestPct,
        date: date ?? this.date,
        dueDate: identical(dueDate, _unset) ? this.dueDate : dueDate as DateTime?,
      );
}

/// Juros retroativos de um empréstimo lançado com data passada: um lançamento
/// "cheio" (taxa × principal) para cada mês completo entre a data do empréstimo
/// e hoje. Ex.: empréstimo de 2 meses atrás a 10% de R$500 → 2× R$50.
List<({DateTime date, double amount})> retroactiveLoanInterest({
  required DateTime loanDate,
  required double principal,
  required double interestPct,
  required DateTime now,
}) {
  final months = (now.year * 12 + now.month) - (loanDate.year * 12 + loanDate.month);
  if (months <= 0 || interestPct <= 0 || principal <= 0) return const [];
  final amount = double.parse((principal * interestPct / 100).toStringAsFixed(2));
  return [
    for (var i = 1; i <= months; i++)
      (date: DateTime(loanDate.year, loanDate.month + i, 1), amount: amount),
  ];
}

const Object _unset = Object();

/// Projeção (ESTIMATIVA) do crescimento da caixinha assumindo que todos os
/// participantes aportam a cota em dia todo mês e o dinheiro rende a uma taxa
/// média mensal informada. Não considera empréstimos (entre participantes ou
/// externos) — é só uma simulação de poupança.
@immutable
class CaixinhaProjection {
  final double projectedTotal;
  final double totalContributed;
  final double estimatedYield;
  final double perParticipant;
  final int months;
  final double monthlyRatePct;

  const CaixinhaProjection({
    required this.projectedTotal,
    required this.totalContributed,
    required this.estimatedYield,
    required this.perParticipant,
    required this.months,
    required this.monthlyRatePct,
  });

  /// Simula [months] meses: a cada mês o saldo rende [monthlyRatePct]% e recebe
  /// os aportes ([participants] × [monthlyContribution]). Começa em [startBalance].
  static CaixinhaProjection simulate({
    required double startBalance,
    required int participants,
    required double monthlyContribution,
    required int months,
    required double monthlyRatePct,
  }) {
    final r = monthlyRatePct / 100;
    final monthlyIn = participants * monthlyContribution;
    var balance = startBalance;
    for (var i = 0; i < months; i++) {
      balance = balance * (1 + r) + monthlyIn;
    }
    final contributed = startBalance + monthlyIn * months;
    return CaixinhaProjection(
      projectedTotal: balance,
      totalContributed: contributed,
      estimatedYield: balance - contributed,
      perParticipant: participants == 0 ? 0 : balance / participants,
      months: months,
      monthlyRatePct: monthlyRatePct,
    );
  }
}

/// Uma pessoa na projeção: quanto terá colocado e o saldo projetado.
@immutable
class ProjectionPerson {
  final String personId;
  final String name;
  final double contributed; // total que terá aportado (atual + futuro)
  final double projected; // saldo projetado no fim
  const ProjectionPerson({required this.personId, required this.name, required this.contributed, required this.projected});
  double get profit => projected - contributed;
}

/// Resultado detalhado da projeção: totais + quebra por pessoa.
@immutable
class ProjectionResult {
  final int months;
  final double monthlyRatePct;
  final double totalContributed;
  final double totalProjected;
  final List<ProjectionPerson> people;
  const ProjectionResult({
    required this.months,
    required this.monthlyRatePct,
    required this.totalContributed,
    required this.totalProjected,
    required this.people,
  });
  double get totalYield => totalProjected - totalContributed;
}

/// Juro de atraso **cristalizado**: quando a cota de um mês vencido é paga mas o
/// juro que ela vinha gerando NÃO é pago junto, esse juro deixa de ser derivável
/// (o mês não está mais em aberto) e vira uma dívida registrada aqui — assim ele
/// não some do radar. É quitado depois, virando rendimento da caixinha.
///
/// [amount] é o juro devido; [paidAmount] o quanto dele já foi pago. Não volta a
/// compor juros (já foi composto até a cristalização) — decisão de projeto para
/// um grupo informal, documentada em `fechai-docs/CAIXINHA.md`.
@immutable
class CotaInterestCharge {
  final String id;
  final String memberId;
  final double amount;
  final double paidAmount;
  final DateTime date;
  final String? note;
  final String? recordedBy;

  const CotaInterestCharge({
    required this.id,
    required this.memberId,
    required this.amount,
    this.paidAmount = 0,
    required this.date,
    this.note,
    this.recordedBy,
  });

  /// Quanto ainda falta pagar deste juro.
  double get outstanding {
    final o = amount - paidAmount;
    return o < 0.005 ? 0 : double.parse(o.toStringAsFixed(2));
  }

  bool get isSettled => outstanding <= 0.005;
}

/// Situação de atraso das cotas de um participante: quanto de cota venceu e não
/// foi paga ([principal]) e os juros devidos ([interest]) — que somam os juros
/// ainda deriváveis dos meses em aberto (compostos ao mês, como um empréstimo)
/// com os juros já cristalizados ([carriedInterest], ver [CotaInterestCharge]).
/// [months] é o nº de meses vencidos em aberto; [oldestDue] é o 1º mês em atraso.
@immutable
class CotaArrears {
  final double principal;
  final double interest;
  final int months;
  final DateTime? oldestDue;

  /// Parcela de [interest] que já foi cristalizada (dívida registrada), isto é,
  /// não depende mais dos meses em aberto.
  final double carriedInterest;

  const CotaArrears({
    required this.principal,
    required this.interest,
    required this.months,
    this.oldestDue,
    this.carriedInterest = 0,
  });

  static const none = CotaArrears(principal: 0, interest: 0, months: 0);

  /// Juros ainda deriváveis dos meses em aberto (o que some se eles forem pagos).
  double get derivedInterest {
    final d = interest - carriedInterest;
    return d < 0 ? 0 : double.parse(d.toStringAsFixed(2));
  }

  double get total => principal + interest;
  bool get isLate => total > 0.005;
  bool get hasInterest => interest > 0.005;
}

/// Plano de uma quitação de cotas em atraso: o que será lançado se o valor
/// informado for confirmado. Puro (não escreve nada) — a UI mostra a prévia com
/// os mesmos números que serão gravados. Ver [Caixinha.planCotaSettlement].
@immutable
class CotaSettlementPlan {
  /// Aportes a lançar, datados no vencimento de cada mês (mais antigo primeiro).
  final List<({DateTime month, double amount})> fills;

  /// Juros efetivamente pagos agora (viram rendimento da caixinha).
  final double interestPaid;

  /// Abatimentos em cobranças de juro já cristalizadas (mais antigas primeiro).
  final List<({String chargeId, double amount})> chargePayments;

  /// Juro que deixou de ser derivável (a cota saiu do atraso) e NÃO foi pago —
  /// vira uma cobrança cristalizada para não sumir do radar.
  final double newCharge;

  final double principalPaid;
  final double freedInterest;
  final double interestDue;
  final double remainingDebt;
  final int monthsCleared;
  final DateTime? partialMonth;
  final double partialAmount;

  const CotaSettlementPlan({
    required this.fills,
    required this.interestPaid,
    required this.chargePayments,
    required this.newCharge,
    required this.principalPaid,
    required this.freedInterest,
    required this.interestDue,
    required this.remainingDebt,
    required this.monthsCleared,
    this.partialMonth,
    this.partialAmount = 0,
  });

  bool get isEmpty => fills.isEmpty && interestPaid <= 0.005;
}

/// Um ponto mensal da evolução da caixinha: quanto foi aportado (sem
/// rendimento) e o patrimônio (com rendimento) acumulados até aquele mês.
/// [projected] marca os meses estimados no futuro.
@immutable
class CaixinhaSeriesPoint {
  final DateTime month; // 1º dia do mês
  final double contributed; // acumulado, só aportes (sem rendimento)
  final double patrimony; // acumulado com rendimento
  final bool projected;
  const CaixinhaSeriesPoint({
    required this.month,
    required this.contributed,
    required this.patrimony,
    this.projected = false,
  });
}

/// Unidades de participação por pessoa após replay cronológico dos eventos.
@immutable
class _Shares {
  final Map<String, double> unitsByPerson;
  final double totalUnits;
  const _Shares(this.unitsByPerson, this.totalUnits);
}

/// Caixinha: poupança coletiva com empréstimos a juros combinados. Vários
/// membros aportam mensalmente, o dinheiro rende (banco + juros de empréstimo)
/// e no fim o período é estendido ou partilhado — cada um leva sua parte
/// proporcional ao quanto pôs **e por quanto tempo** (participação × tempo).
@immutable
class Caixinha {
  final String id;
  final String name;
  final String emoji;
  final String ownerId;

  /// Juros padrão dos empréstimos (ao mês), editável por caixinha — não é fixo.
  final double defaultInterestPct;

  /// Valor da cota por participante (quanto cada um coloca por mês). É o valor
  /// usado como aporte padrão sugerido e base da projeção.
  final double monthlyQuota;

  /// Dia do mês em que a cota vence (aniversário mensal). Null = sem data de
  /// pagamento definida (não há atraso com juros). A partir desse dia, a cota
  /// não paga acumula juros à taxa [defaultInterestPct].
  final int? paymentDay;

  final CaixinhaStatus status;
  final DateTime createdAt;
  final DateTime? closedAt;

  /// Início da primeira parcela (quando começam os aportes). Cai em [createdAt]
  /// quando não informado.
  final DateTime? startDate;

  /// Fim do período, se houver limite (opcional).
  final DateTime? endDate;

  final List<CaixinhaMember> members;
  final List<Contribution> contributions;
  final List<Earning> earnings;
  final List<Loan> loans;
  final List<LoanPayment> loanPayments;
  final List<MemberExit> exits;
  final List<Adjustment> adjustments;

  /// Juros de atraso já cristalizados (devidos mesmo com a cota paga).
  final List<CotaInterestCharge> cotaCharges;

  const Caixinha({
    required this.id,
    required this.name,
    required this.emoji,
    this.ownerId = 'me',
    this.defaultInterestPct = 0,
    this.monthlyQuota = 0,
    this.paymentDay,
    this.status = CaixinhaStatus.open,
    required this.createdAt,
    this.closedAt,
    this.startDate,
    this.endDate,
    required this.members,
    this.contributions = const [],
    this.earnings = const [],
    this.loans = const [],
    this.loanPayments = const [],
    this.exits = const [],
    this.adjustments = const [],
    this.cotaCharges = const [],
  });

  bool get isOwner => ownerId == 'me';
  bool get isOpen => status == CaixinhaStatus.open;
  bool get isClosed => status == CaixinhaStatus.closed;

  bool isTreasurer(String personId) {
    if (personId == ownerId || (personId == 'me' && isOwner)) return true;
    return memberById(personId)?.isTreasurer ?? false;
  }

  bool get iAmTreasurer => isTreasurer('me');

  CaixinhaMember? memberById(String personId) {
    for (final m in members) {
      if (m.person.id == personId) return m;
    }
    return null;
  }

  String nameOf(String personId) =>
      personId == 'me' ? 'Você' : (memberById(personId)?.person.name ?? '—');

  /// Nome completo (nome + sobrenome) de um participante, para o histórico.
  String fullNameOf(String personId) =>
      personId == 'me' ? 'Você' : (memberById(personId)?.person.fullName ?? '—');

  /// Membros que participam da poupança (exclui tomadores externos e quem saiu).
  List<CaixinhaMember> get contributingMembers =>
      members.where((m) => m.contributes && !hasExited(m.person.id)).toList();

  /// Tomadores externos cadastrados (só pegaram empréstimo).
  List<CaixinhaMember> get borrowers => members.where((m) => m.isBorrower).toList();

  /// Participantes que já saíram (para o histórico).
  List<CaixinhaMember> get exitedMembers =>
      members.where((m) => m.contributes && hasExited(m.person.id)).toList();

  bool hasExited(String personId) => exits.any((e) => e.memberId == personId);
  double exitRefundOf(String personId) =>
      exits.where((e) => e.memberId == personId).fold(0.0, (a, e) => a + e.refund);
  double get totalRefunds => exits.fold(0.0, (a, e) => a + e.refund);

  int get acceptedMembersCount => contributingMembers.where((m) => m.inviteAccepted).length;

  /// Nº de participantes da poupança (aceitos + pendentes) — o que a lista mostra.
  int get memberCount => contributingMembers.length;

  /// Início efetivo da caixinha (1ª parcela) — cai em [createdAt] se não informado.
  DateTime get periodStart => startDate ?? createdAt;

  /// Duração do período em meses, quando há data-fim (mín. 1); senão null.
  int? get periodMonths {
    if (endDate == null) return null;
    final m = (endDate!.year - periodStart.year) * 12 + (endDate!.month - periodStart.month);
    return m < 1 ? 1 : m;
  }

  /// Aporte mensal sugerido para um participante: nº de cotas × valor da cota.
  double suggestedAporteFor(String personId) =>
      (memberById(personId)?.quotas ?? 1) * monthlyQuota;

  /// Quanto uma pessoa aportou dentro de um mês (competência de [ref]).
  double contributedInMonth(String personId, DateTime ref) {
    final ix = _monthIndex(ref);
    return contributions
        .where((c) => c.personId == personId && _monthIndex(c.date) == ix)
        .fold(0.0, (a, c) => a + c.amount);
  }

  /// Quanto ainda falta da cota do mês de [ref] (0 se já pagou). Usa o aporte
  /// sugerido (cotas × valor da cota) como esperado.
  double cotaPendingThisMonth(String personId, DateTime ref) {
    final expected = suggestedAporteFor(personId);
    if (expected <= 0) return 0;
    final paid = contributedInMonth(personId, ref);
    final left = expected - paid;
    return left < 0.005 ? 0 : left;
  }

  /// Taxa média mensal usada na projeção do gráfico quando nenhuma é informada.
  static const double defaultProjectionRatePct = 0.5;

  /// Meses (1º dia) dentro do período [periodStart..agora] com cota pendente.
  /// [onlyMe] restringe às pendências do próprio usuário (membro comum);
  /// `false` considera qualquer participante (visão de tesoureiro/dono).
  List<DateTime> monthsWithPendencies({required bool onlyMe, DateTime? now}) {
    if (monthlyQuota <= 0) return const [];
    final ref = now ?? DateTime.now();
    final start = DateTime(periodStart.year, periodStart.month);
    final end = DateTime(ref.year, ref.month);
    // Inclui convidados pendentes: o dono/tesoureiro acompanha quem adicionou
    // mesmo sem aceite (grupo de confiança / migração do caderno). Só exclui
    // quem recusou.
    final ativos = contributingMembers.where((m) => !m.inviteDeclined).toList();
    final result = <DateTime>[];
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month + 1)) {
      final pending = onlyMe
          ? cotaPendingThisMonth('me', d) > 0.005
          : ativos.any((m) => cotaPendingThisMonth(m.person.id, d) > 0.005);
      if (pending) result.add(d);
    }
    return result;
  }

  /// Dia do aniversário (vencimento) da cota no mês [y]/[m], respeitando o
  /// último dia de meses curtos (ex.: dia 31 vira 28/fev).
  DateTime _annivIn(int y, int m) {
    final day = paymentDay ?? 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, day < lastDay ? day : lastDay);
  }

  /// Situação de atraso das cotas de um participante em [now]. Para cada mês
  /// cujo aniversário (dia de pagamento) já passou e a cota não foi paga, o
  /// valor entra no saldo devedor e, a cada mês seguinte em aberto, os juros
  /// (`defaultInterestPct`) incidem sobre o saldo — compostos, como se a pessoa
  /// fosse "pegando emprestado" a diferença. Requer [paymentDay] definido.
  /// Juros de atraso cristalizados e ainda não pagos de um participante.
  double carriedInterestOf(String personId) => double.parse(cotaCharges
      .where((x) => x.memberId == personId)
      .fold(0.0, (a, x) => a + x.outstanding)
      .toStringAsFixed(2));

  /// Cobranças de juro cristalizado em aberto (mais antigas primeiro) — a
  /// quitação abate nesta ordem.
  List<CotaInterestCharge> openCotaChargesOf(String personId) =>
      (cotaCharges.where((x) => x.memberId == personId && !x.isSettled).toList()
        ..sort((a, b) => a.date.compareTo(b.date)));

  CotaArrears cotaArrearsOf(String personId, {DateTime? now}) {
    final carried = carriedInterestOf(personId);
    final q = suggestedAporteFor(personId);
    if (q <= 0 || paymentDay == null) {
      // Sem cota/vencimento não há novo atraso, mas juro já cristalizado continua devido.
      return carried <= 0.005
          ? CotaArrears.none
          : CotaArrears(principal: 0, interest: carried, months: 0, carriedInterest: carried);
    }
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final i = defaultInterestPct / 100;
    final startIx = _monthIndex(periodStart);
    final endIx = _monthIndex(today);
    double principal = 0, interest = 0;
    int months = 0;
    DateTime? oldest;
    var first = true;
    for (var ix = startIx; ix <= endIx; ix++) {
      final m = ((ix - 1) % 12) + 1;
      final y = (ix - m) ~/ 12;
      if (!_annivIn(y, m).isBefore(today)) continue; // ainda não venceu
      if (!first && (principal + interest) > 0.005) {
        interest += (principal + interest) * i; // juros do mês decorrido
      }
      first = false;
      final short = q - contributedInMonth(personId, DateTime(y, m));
      if (short > 0.005) {
        principal += short;
        months++;
        oldest ??= DateTime(y, m);
      } else if (short < -0.005) {
        // Pagou além da cota do mês: o excedente abate juros e depois principal.
        var credit = -short;
        final payInt = math.min(credit, interest);
        interest -= payInt;
        credit -= payInt;
        principal = math.max(0, principal - credit);
      }
    }
    return CotaArrears(
      principal: double.parse(principal.toStringAsFixed(2)),
      // Juros devidos = o que ainda deriva dos meses em aberto + o cristalizado.
      interest: double.parse((interest + carried).toStringAsFixed(2)),
      months: months,
      oldestDue: oldest,
      carriedInterest: carried,
    );
  }

  /// Meses vencidos e ainda não pagos de um participante (o mais antigo
  /// primeiro), com o quanto falta em cada um. Base para alocar a quitação do
  /// atraso mês a mês.
  List<({DateTime month, double shortfall})> overdueMonths(String personId, {DateTime? now}) {
    final q = suggestedAporteFor(personId);
    if (q <= 0 || paymentDay == null) return const [];
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final startIx = _monthIndex(periodStart);
    final endIx = _monthIndex(today);
    final out = <({DateTime month, double shortfall})>[];
    for (var ix = startIx; ix <= endIx; ix++) {
      final m = ((ix - 1) % 12) + 1;
      final y = (ix - m) ~/ 12;
      if (!_annivIn(y, m).isBefore(today)) continue;
      final short = q - contributedInMonth(personId, DateTime(y, m));
      if (short > 0.005) out.add((month: DateTime(y, m), shortfall: double.parse(short.toStringAsFixed(2))));
    }
    return out;
  }

  /// Data de vencimento da cota de um mês (dia do pagamento, ajustado a meses curtos).
  DateTime dueDateOfMonth(DateTime month) => _annivIn(month.year, month.month);

  /// Monta o plano de uma quitação de [amount] para [personId] — quem paga aos
  /// poucos. O valor abate os meses vencidos **do mais antigo para o mais novo**
  /// (o que sobrar fica de parcial na cota seguinte) e só depois os juros.
  ///
  /// A regra que mantém o modelo justo: ao pagar a cota de um mês vencido, o
  /// juro que aquele mês vinha gerando deixa de ser derivável — se ele NÃO foi
  /// pago junto, vira uma cobrança cristalizada ([CotaSettlementPlan.newCharge]).
  /// Assim o juro devido nunca é perdido, mesmo em pagamento parcial.
  ///
  /// Com [chargeInterest] `false` ("pagou em dia"), o juro dos meses corrigidos é
  /// perdoado — é uma correção de registro, não uma cobrança. Juros já
  /// cristalizados continuam devidos nos dois modos.
  CotaSettlementPlan planCotaSettlement(
    String personId, {
    required double amount,
    bool chargeInterest = true,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final before = cotaArrearsOf(personId, now: ref);
    var rem = amount <= 0 ? 0.0 : amount;

    // 1) Principal: meses vencidos, do mais antigo ao mais novo.
    final fills = <({DateTime month, double amount})>[];
    var monthsCleared = 0;
    DateTime? partialMonth;
    var partialAmount = 0.0;
    for (final om in overdueMonths(personId, now: ref)) {
      if (rem <= 0.005) break;
      final pay = double.parse(math.min(rem, om.shortfall).toStringAsFixed(2));
      if (pay <= 0.005) break;
      rem -= pay;
      fills.add((month: om.month, amount: pay));
      if (pay >= om.shortfall - 0.005) {
        monthsCleared++;
      } else {
        partialMonth = om.month;
        partialAmount = pay;
      }
    }
    final principalPaid = double.parse(fills.fold(0.0, (a, f) => a + f.amount).toStringAsFixed(2));

    // 2) Juro que deixa de ser derivável por causa desses aportes (delta exato,
    // usando a própria conta de `cotaArrearsOf` sobre uma cópia hipotética).
    var freed = 0.0;
    if (fills.isNotEmpty) {
      final hipo = copyWith(contributions: [
        ...contributions,
        for (final f in fills)
          Contribution(id: '_plan', personId: personId, amount: f.amount, date: dueDateOfMonth(f.month)),
      ]);
      freed = before.derivedInterest - hipo.cotaArrearsOf(personId, now: ref).derivedInterest;
      if (freed < 0.005) freed = 0;
      freed = double.parse(freed.toStringAsFixed(2));
    }

    // 3) Juros: paga o cristalizado (mais antigo primeiro) e depois o liberado.
    final interestDue = chargeInterest
        ? double.parse((before.carriedInterest + freed).toStringAsFixed(2))
        : 0.0;
    final interestPaid = double.parse(math.min(rem, interestDue).toStringAsFixed(2));
    rem -= interestPaid;

    var left = interestPaid;
    final chargePayments = <({String chargeId, double amount})>[];
    if (chargeInterest) {
      for (final ch in openCotaChargesOf(personId)) {
        if (left <= 0.005) break;
        final p = double.parse(math.min(left, ch.outstanding).toStringAsFixed(2));
        left -= p;
        chargePayments.add((chargeId: ch.id, amount: p));
      }
    }
    // O que sobrou de `interestPaid` depois das cobranças antigas pagou o juro
    // recém-liberado; o restante dele precisa ser cristalizado.
    final newCharge = chargeInterest
        ? double.parse(math.max(0.0, freed - left).toStringAsFixed(2))
        : 0.0;

    // "Pagou em dia" perdoa o juro dos meses corrigidos (correção de registro).
    final forgiven = chargeInterest ? 0.0 : freed;
    final remaining = before.total - principalPaid - interestPaid - forgiven;

    return CotaSettlementPlan(
      fills: fills,
      interestPaid: interestPaid,
      chargePayments: chargePayments,
      newCharge: newCharge,
      principalPaid: principalPaid,
      freedInterest: freed,
      interestDue: interestDue,
      remainingDebt: double.parse(math.max(0.0, remaining).toStringAsFixed(2)),
      monthsCleared: monthsCleared,
      partialMonth: partialMonth,
      partialAmount: partialAmount,
    );
  }

  /// Série mensal para o gráfico de evolução: do início da caixinha até hoje
  /// (histórico real) + [projectMonths] meses de projeção (todos aportando a
  /// cota, patrimônio rendendo [projectionRatePct]% ao mês). Reaproveita a
  /// competência mensal (`_monthIndex`) dos aportes/rendimentos/ajustes/saídas.
  List<CaixinhaSeriesPoint> monthlySeries({
    int projectMonths = 12,
    double? projectionRatePct,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final startIx = _monthIndex(periodStart);
    final endIx = _monthIndex(ref) < startIx ? startIx : _monthIndex(ref);

    double sumIn(Iterable<({int ix, double v})> xs, int ix) =>
        xs.where((x) => x.ix == ix).fold(0.0, (a, x) => a + x.v);
    final contribEv = [for (final c in contributions) (ix: _monthIndex(c.date), v: c.amount)];
    final earnEv = [for (final e in earnings) (ix: _monthIndex(e.date), v: e.amount)];
    final adjEv = [for (final a in adjustments) (ix: _monthIndex(a.date), v: a.delta)];
    final exitEv = [for (final x in exits) (ix: _monthIndex(x.date), v: x.refund)];

    DateTime monthOf(int ix) {
      final month = ((ix - 1) % 12) + 1;
      final year = (ix - month) ~/ 12;
      return DateTime(year, month);
    }

    final points = <CaixinhaSeriesPoint>[];
    var contribAcc = 0.0, patrAcc = 0.0;
    for (var ix = startIx; ix <= endIx; ix++) {
      final refunds = sumIn(exitEv, ix);
      contribAcc += sumIn(contribEv, ix) - refunds;
      patrAcc += sumIn(contribEv, ix) + sumIn(earnEv, ix) + sumIn(adjEv, ix) - refunds;
      points.add(CaixinhaSeriesPoint(month: monthOf(ix), contributed: contribAcc, patrimony: patrAcc));
    }

    // Projeção (tracejada): vai até o FIM da caixinha quando há data-limite;
    // sem limite, projeta [projectMonths] meses à frente. Não considera
    // empréstimos — só aportes da cota + rendimento médio.
    if (isOpen) {
      final horizon = endDate != null
          ? (_monthIndex(endDate!) - endIx).clamp(0, 120)
          : projectMonths;
      final r = (projectionRatePct ?? defaultProjectionRatePct) / 100;
      // Convidados pendentes contam na projeção (mesma regra das cotas): só quem
      // recusou fica de fora.
      final active = contributingMembers.where((m) => !m.inviteDeclined);
      final monthlyIn = active.fold(0.0, (a, m) => a + suggestedAporteFor(m.person.id));
      var pc = contribAcc, pp = patrAcc;
      for (var i = 1; i <= horizon; i++) {
        pp = pp * (1 + r) + monthlyIn;
        pc = pc + monthlyIn;
        points.add(CaixinhaSeriesPoint(month: monthOf(endIx + i), contributed: pc, patrimony: pp, projected: true));
      }
    }
    return points;
  }

  /// Projeção "se todos pagarem em dia": simula os próximos [months] meses com a
  /// mesma mecânica de unidades (cada um aporta a cota, o total rende a taxa
  /// média) e devolve a quebra por pessoa. NÃO considera empréstimos.
  ProjectionResult project({required int months, required double monthlyRatePct}) {
    final r = monthlyRatePct / 100;
    final active = contributingMembers;
    final units = {for (final m in active) m.person.id: unitsOf(m.person.id)};
    final contributed = {for (final m in active) m.person.id: refundBaseOf(m.person.id)};
    var totalUnits = units.values.fold(0.0, (a, b) => a + b);
    var patr = patrimony;
    for (var i = 0; i < months; i++) {
      final uv = totalUnits <= 0 ? _initialUnitValue : patr / totalUnits;
      for (final m in active) {
        final add = suggestedAporteFor(m.person.id);
        if (add > 0) {
          units[m.person.id] = units[m.person.id]! + add / uv;
          totalUnits += add / uv;
          patr += add;
          contributed[m.person.id] = contributed[m.person.id]! + add;
        }
      }
      patr *= (1 + r); // rendimento do mês sobre o total
    }
    final finalUv = totalUnits <= 0 ? _initialUnitValue : patr / totalUnits;
    final people = [
      for (final m in active)
        ProjectionPerson(
          personId: m.person.id,
          name: m.person.id == 'me' ? 'Você' : m.person.name,
          contributed: contributed[m.person.id]!,
          projected: units[m.person.id]! * finalUv,
        ),
    ]..sort((a, b) => b.projected.compareTo(a.projected));
    return ProjectionResult(
      months: months,
      monthlyRatePct: monthlyRatePct,
      totalContributed: contributed.values.fold(0.0, (a, b) => a + b),
      totalProjected: patr,
      people: people,
    );
  }

  // ---- Dinheiro ----

  double get totalContributed => contributions.fold(0.0, (a, c) => a + c.amount);
  double get totalEarnings => earnings.fold(0.0, (a, e) => a + e.amount);
  double get investmentEarnings =>
      earnings.where((e) => e.source == EarningSource.investment).fold(0.0, (a, e) => a + e.amount);
  double get loanEarnings =>
      earnings.where((e) => e.source == EarningSource.loanInterest).fold(0.0, (a, e) => a + e.amount);

  double get totalAdjustments => adjustments.fold(0.0, (a, x) => a + x.delta);
  double adjustedBy(String personId) =>
      adjustments.where((x) => x.memberId == personId).fold(0.0, (a, x) => a + x.delta);

  /// Patrimônio total = tudo aportado + tudo rendido + ajustes − devoluções de
  /// saída. Emprestar só troca caixa por "a receber", não muda o patrimônio.
  double get patrimony => totalContributed + totalEarnings + totalAdjustments - totalRefunds;

  /// Base de devolução na saída: o que a pessoa aportou + ajustes manuais dela
  /// (sem o rendimento).
  double refundBaseOf(String personId) => contributedBy(personId) + adjustedBy(personId);

  /// Juros já lançados (como rendimento) de um empréstimo.
  double accruedInterestOf(String loanId) =>
      earnings.where((e) => e.loanId == loanId).fold(0.0, (a, e) => a + e.amount);

  /// Total já pago (parcial ou integral) num empréstimo.
  double repaidOf(String loanId) =>
      loanPayments.where((p) => p.loanId == loanId).fold(0.0, (a, p) => a + p.amount);

  List<LoanPayment> paymentsOf(String loanId) =>
      (loanPayments.where((p) => p.loanId == loanId).toList()..sort((a, b) => a.date.compareTo(b.date)));

  /// Saldo devedor de um empréstimo: principal + juros acumulados − o que já foi
  /// pago. É sobre esse saldo que os próximos juros devem incidir.
  double outstandingOf(Loan loan) {
    final o = loan.principal + accruedInterestOf(loan.id) - repaidOf(loan.id);
    return o < 0 ? 0 : o;
  }

  bool isSettled(Loan loan) => outstandingOf(loan) <= 0.005;

  /// Empréstimo dado como PERDA (calote): há um rendimento negativo amarrado a
  /// ele, que zerou o "a receber" e baixou o patrimônio de todos.
  bool isWrittenOff(Loan loan) => earnings.any((e) => e.loanId == loan.id && e.amount < 0);

  /// Empréstimo "pra dentro" (tomador é um membro contribuinte) vs "pra fora".
  bool loanIsInternal(Loan loan) => memberById(loan.borrowerPersonId)?.contributes ?? false;

  List<Loan> get openLoans => loans.where((l) => !isSettled(l)).toList();

  /// Total a receber de todos os empréstimos (quitados contam 0) — está
  /// emprestado, fora do caixa.
  double get outstandingReceivables => loans.fold(0.0, (a, l) => a + outstandingOf(l));

  /// Dinheiro efetivamente disponível em caixa.
  double get cashOnHand => patrimony - outstandingReceivables;

  // ---- Participação (fundo: unidade × tempo) ----

  static const double _initialUnitValue = 1.0;

  /// Competência mensal de uma data (ano×12+mês). A participação é calculada por
  /// MÊS, não por dia: as cotas são mensais, então quem aportou no dia 1 ou no
  /// dia 5 do mesmo mês entra igual no rendimento daquele mês.
  static int _monthIndex(DateTime d) => d.year * 12 + d.month;

  _Shares _foldShares() {
    // kind: 0 aporte (compra unidades), 1 rendimento (valoriza a unidade),
    // 2 saída (remove as unidades do participante e paga o reembolso).
    final events = <({DateTime date, int kind, String? personId, double amount})>[
      for (final c in contributions) (date: c.date, kind: 0, personId: c.personId, amount: c.amount),
      // Ajuste manual entra como "compra/venda" de unidades (delta com sinal).
      for (final x in adjustments) (date: x.date, kind: 0, personId: x.memberId, amount: x.delta),
      for (final e in earnings) (date: e.date, kind: 1, personId: null, amount: e.amount),
      for (final x in exits) (date: x.date, kind: 2, personId: x.memberId, amount: x.refund),
    ]..sort((a, b) {
        // Ordena por MÊS (não por dia); dentro do mês: aporte < rendimento < saída.
        // Assim, todos os aportes do mês compram unidades pelo mesmo valor (o do
        // início do mês) e o rendimento do mês é repartido entre todos eles.
        final d = _monthIndex(a.date).compareTo(_monthIndex(b.date));
        return d != 0 ? d : a.kind.compareTo(b.kind);
      });

    final units = <String, double>{};
    double totalUnits = 0;
    double patr = 0;
    for (final ev in events) {
      if (ev.kind == 0) {
        final uv = totalUnits == 0 ? _initialUnitValue : patr / totalUnits;
        final issued = uv == 0 ? 0.0 : ev.amount / uv;
        units[ev.personId!] = (units[ev.personId] ?? 0) + issued;
        totalUnits += issued;
        patr += ev.amount;
      } else if (ev.kind == 1) {
        patr += ev.amount;
      } else {
        // Saída: tira as unidades do participante e paga só o reembolso. O lucro
        // que ele deixa fica diluído nas unidades de quem permanece.
        final u = units[ev.personId] ?? 0;
        totalUnits -= u;
        units[ev.personId!] = 0;
        patr -= ev.amount;
      }
    }
    return _Shares(units, totalUnits);
  }

  /// Valor atual de uma unidade de participação (começa em R$ 1,00).
  double get unitValue {
    final s = _foldShares();
    return s.totalUnits == 0 ? _initialUnitValue : patrimony / s.totalUnits;
  }

  double unitsOf(String personId) => _foldShares().unitsByPerson[personId] ?? 0;

  /// Fatia (0..1) de uma pessoa no patrimônio atual.
  double participationOf(String personId) {
    final s = _foldShares();
    return s.totalUnits == 0 ? 0 : (s.unitsByPerson[personId] ?? 0) / s.totalUnits;
  }

  /// Quanto a pessoa acumulou — o que receberia se a caixinha fosse partilhada
  /// hoje (participação × patrimônio).
  double balanceOf(String personId) => participationOf(personId) * patrimony;

  double contributedBy(String personId) =>
      contributions.where((c) => c.personId == personId).fold(0.0, (a, c) => a + c.amount);

  /// Lucro acumulado da pessoa (o que rendeu além do que ela pôs).
  double profitOf(String personId) => balanceOf(personId) - contributedBy(personId);

  /// Extrato: todas as movimentações que mexem no patrimônio (aporte, ajuste,
  /// rendimento, saída), em ordem cronológica, com o patrimônio resultante
  /// depois de cada uma. Empréstimos/pagamentos ficam na seção própria (não
  /// mudam o patrimônio). Do início ao atual.
  List<CaixinhaMovement> get movements {
    // Nome de quem lançou — só quando conhecido e diferente da pessoa-alvo (o
    // caso comum é o tesoureiro lançando pelos membros).
    String? by(String? recorder, String? subject) {
      if (recorder == null || recorder == subject) return null;
      return fullNameOf(recorder);
    }

    final raw = <({DateTime date, int order, MovementKind kind, String label, double amount, String? by})>[
      for (final c in contributions)
        (date: c.date, order: 0, kind: MovementKind.contribution, label: 'Aporte · ${fullNameOf(c.personId)}', amount: c.amount, by: by(c.recordedBy, c.personId)),
      for (final a in adjustments)
        (date: a.date, order: 0, kind: MovementKind.adjustment, label: 'Ajuste manual · ${fullNameOf(a.memberId)}', amount: a.delta, by: by(a.recordedBy, a.memberId)),
      for (final e in earnings)
        (date: e.date, order: 1, kind: MovementKind.earning, label: e.note ?? (e.fromLoan ? 'Juros de empréstimo' : 'Rendimento'), amount: e.amount, by: by(e.recordedBy, null)),
      for (final x in exits)
        (date: x.date, order: 2, kind: MovementKind.exit, label: '${fullNameOf(x.memberId)} saiu (devolução)', amount: -x.refund, by: by(x.recordedBy, x.memberId)),
    ]..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.order.compareTo(b.order);
      });
    var running = 0.0;
    return [
      for (final m in raw)
        CaixinhaMovement(
          date: m.date,
          kind: m.kind,
          label: m.label,
          amount: m.amount,
          balanceAfter: running += m.amount,
          recordedByName: m.by,
        ),
    ];
  }

  Caixinha copyWith({
    String? name,
    String? emoji,
    double? defaultInterestPct,
    double? monthlyQuota,
    int? paymentDay,
    CaixinhaStatus? status,
    DateTime? closedAt,
    DateTime? startDate,
    DateTime? endDate,
    List<CaixinhaMember>? members,
    List<Contribution>? contributions,
    List<Earning>? earnings,
    List<Loan>? loans,
    List<LoanPayment>? loanPayments,
    List<MemberExit>? exits,
    List<Adjustment>? adjustments,
    List<CotaInterestCharge>? cotaCharges,
  }) =>
      Caixinha(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        ownerId: ownerId,
        defaultInterestPct: defaultInterestPct ?? this.defaultInterestPct,
        monthlyQuota: monthlyQuota ?? this.monthlyQuota,
        paymentDay: paymentDay ?? this.paymentDay,
        status: status ?? this.status,
        createdAt: createdAt,
        closedAt: closedAt ?? this.closedAt,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        members: members ?? this.members,
        contributions: contributions ?? this.contributions,
        earnings: earnings ?? this.earnings,
        loans: loans ?? this.loans,
        loanPayments: loanPayments ?? this.loanPayments,
        exits: exits ?? this.exits,
        adjustments: adjustments ?? this.adjustments,
        cotaCharges: cotaCharges ?? this.cotaCharges,
      );
}
