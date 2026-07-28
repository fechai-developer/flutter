import 'package:flutter/foundation.dart';

import '../../core/limits.dart';
import 'person.dart';

/// Status de pagamento de uma cota no ciclo atual.
enum QuotaStatus { pending, paid, overdue }

/// Participante de uma assinatura, com sua cota e status no ciclo corrente.
@immutable
class SubscriptionMember {
  final Person person;
  final double quota; // valor da cota em R$
  final QuotaStatus status;
  final int monthsLate; // meses em atraso (para acréscimo de juros, #2)
  final MemberStatus inviteStatus; // situação do convite (Etapa C)

  /// true = participante removido da assinatura, mas com histórico preservado
  /// (mantém acesso somente-leitura à assinatura e à própria cota).
  final bool removed;

  const SubscriptionMember({
    required this.person,
    required this.quota,
    this.status = QuotaStatus.pending,
    this.monthsLate = 0,
    this.inviteStatus = MemberStatus.accepted,
    this.removed = false,
  });

  bool get inviteAccepted => inviteStatus == MemberStatus.accepted;
  bool get inviteDeclined => inviteStatus == MemberStatus.declined;
  bool get invitePending => inviteStatus == MemberStatus.pending;

  /// Valor a cobrar já com os juros do atraso aplicados (#2).
  double amountDue(double monthlyInterestPct) =>
      status == QuotaStatus.overdue
          ? InterestPolicy.accrue(quota, monthlyInterestPct, monthsLate)
          : quota;

  /// Só os juros acumulados (0 se não está em atraso).
  double interest(double monthlyInterestPct) =>
      status == QuotaStatus.overdue
          ? InterestPolicy.interestOnly(quota, monthlyInterestPct, monthsLate)
          : 0;

  SubscriptionMember copyWith({double? quota, QuotaStatus? status, int? monthsLate, MemberStatus? inviteStatus, bool? removed}) =>
      SubscriptionMember(
        person: person,
        quota: quota ?? this.quota,
        status: status ?? this.status,
        monthsLate: monthsLate ?? this.monthsLate,
        inviteStatus: inviteStatus ?? this.inviteStatus,
        removed: removed ?? this.removed,
      );
}

/// Assinatura compartilhada (Netflix, Spotify, Microsoft 365...).
@immutable
class Subscription {
  final String id;
  final String serviceName;
  final String emoji;
  final double totalAmount;
  final int billingDay; // dia do mês (1-31)
  final int quotaCount; // nº de cotas do plano (ex.: 5 telas)
  final double monthlyInterestPct; // juros ao mês por atraso (%)
  final String ownerId;
  final List<SubscriptionMember> members;

  /// true = o usuário logado foi removido desta assinatura (acesso
  /// somente-leitura). Dispara o modo "Arquivado" na UI.
  final bool viewerRemoved;

  const Subscription({
    required this.id,
    required this.serviceName,
    required this.emoji,
    required this.totalAmount,
    required this.billingDay,
    required this.quotaCount,
    required this.monthlyInterestPct,
    required this.ownerId,
    required this.members,
    this.viewerRemoved = false,
  });

  /// Cota "cheia" quando o custo é dividido igualmente pelo nº de cotas.
  double get quotaValue => quotaCount == 0 ? 0 : totalAmount / quotaCount;

  /// Participantes ativos (exclui removidos, que ficam só no histórico).
  List<SubscriptionMember> get activeMembers =>
      members.where((m) => !m.removed).toList();

  int get filledQuotas => activeMembers.length;
  int get openQuotas => (quotaCount - filledQuotas).clamp(0, quotaCount);

  double get collectedThisCycle => activeMembers
      .where((m) => m.status == QuotaStatus.paid)
      .fold(0.0, (acc, m) => acc + m.quota);

  double get pendingThisCycle => activeMembers
      .where((m) => m.status != QuotaStatus.paid)
      .fold(0.0, (acc, m) => acc + m.amountDue(monthlyInterestPct));

  /// Teto legal sugerido de juros ao mês (aviso, não trava rígida).
  /// Ver CLAUDE.md / PRD seção 9 — evitar juros abusivos (Lei de Usura).
  static const double suggestedInterestCap = 1.0; // 1% a.m.

  Subscription copyWith({
    String? serviceName,
    String? emoji,
    double? totalAmount,
    int? billingDay,
    int? quotaCount,
    double? monthlyInterestPct,
    List<SubscriptionMember>? members,
    bool? viewerRemoved,
  }) =>
      Subscription(
        id: id,
        serviceName: serviceName ?? this.serviceName,
        emoji: emoji ?? this.emoji,
        totalAmount: totalAmount ?? this.totalAmount,
        billingDay: billingDay ?? this.billingDay,
        quotaCount: quotaCount ?? this.quotaCount,
        monthlyInterestPct: monthlyInterestPct ?? this.monthlyInterestPct,
        ownerId: ownerId,
        members: members ?? this.members,
        viewerRemoved: viewerRemoved ?? this.viewerRemoved,
      );
}
