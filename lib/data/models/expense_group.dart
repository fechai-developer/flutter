import 'package:flutter/foundation.dart';

import 'expense.dart';
import 'person.dart';

/// Acerto de contas: [fromId] pagou [amount] para [toId]. Registrado quando
/// alguém marca "Já paguei" / "Já recebi" — reduz a dívida no cálculo de saldo.
@immutable
class Payment {
  final String id;
  final String fromId;
  final String toId;
  final double amount;
  final DateTime date;

  const Payment({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.amount,
    required this.date,
  });
}

/// Grupo de despesas de evento (viagem, república, churrasco...).
@immutable
class ExpenseGroup {
  final String id;
  final String name;
  final String emoji;
  final List<Person> members;
  final List<Expense> expenses;
  final List<Payment> payments; // acertos registrados (#4/#5)
  final double monthlyInterestPct; // juros ao mês por atraso (#8), ilustrativo
  final String ownerId; // 'me' se o usuário logado é o criador
  /// Situação do convite por membro (personId → status). Ausente ou 'me' = aceito. (Etapa C)
  final Map<String, MemberStatus> memberStatus;

  /// Ex-membros: personIds de quem foi removido do grupo mas ainda tem
  /// histórico preservado. Continuam em [members] (para resolver nomes de
  /// despesas antigas), mas ficam de fora das movimentações ativas.
  final Set<String> removedMemberIds;

  /// true = o usuário logado foi removido deste grupo (acesso somente-leitura
  /// ao histórico das próprias despesas). Dispara o modo "Arquivado" na UI.
  final bool viewerRemoved;
  final DateTime createdAt;

  const ExpenseGroup({
    required this.id,
    required this.name,
    required this.emoji,
    required this.members,
    required this.expenses,
    this.payments = const [],
    this.monthlyInterestPct = 0,
    this.ownerId = 'me',
    this.memberStatus = const {},
    this.removedMemberIds = const {},
    this.viewerRemoved = false,
    required this.createdAt,
  });

  bool get isOwner => ownerId == 'me';

  /// A pessoa foi removida do grupo (mas o histórico dela permanece)?
  bool isRemoved(String personId) => removedMemberIds.contains(personId);

  /// Membros ativos (exclui removidos) — base para participantes, saldos e
  /// seleção de participantes em novas despesas.
  List<Person> get activeMembers =>
      members.where((m) => !removedMemberIds.contains(m.id)).toList();

  /// O usuário logado é sempre "aceito" na sua própria visão; demais membros
  /// caem em [MemberStatus.accepted] quando não há registro explícito.
  MemberStatus statusOf(String personId) => personId == 'me'
      ? MemberStatus.accepted
      : (memberStatus[personId] ?? MemberStatus.accepted);
  bool isPending(String personId) => statusOf(personId) == MemberStatus.pending;
  bool isDeclined(String personId) => statusOf(personId) == MemberStatus.declined;
  bool isAccepted(String personId) => statusOf(personId) == MemberStatus.accepted;
  bool notAccepted(String personId) => !isAccepted(personId);

  double get total => expenses.fold(0, (acc, e) => acc + e.amount);

  ExpenseGroup copyWith({
    String? name,
    String? emoji,
    List<Person>? members,
    List<Expense>? expenses,
    List<Payment>? payments,
    double? monthlyInterestPct,
    Map<String, MemberStatus>? memberStatus,
    Set<String>? removedMemberIds,
    bool? viewerRemoved,
  }) =>
      ExpenseGroup(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        members: members ?? this.members,
        expenses: expenses ?? this.expenses,
        payments: payments ?? this.payments,
        monthlyInterestPct: monthlyInterestPct ?? this.monthlyInterestPct,
        ownerId: ownerId,
        memberStatus: memberStatus ?? this.memberStatus,
        removedMemberIds: removedMemberIds ?? this.removedMemberIds,
        viewerRemoved: viewerRemoved ?? this.viewerRemoved,
        createdAt: createdAt,
      );

  Person? memberById(String id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }
}
