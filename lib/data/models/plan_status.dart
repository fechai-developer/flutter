import 'package:flutter/foundation.dart';

/// Status do plano do usuário logado — alimenta o gating comercial na UI
/// (recursos premium mostrados desabilitados + upsell). Espelha o RPC
/// `my_plan_status()` no Supabase; no mock é montado a partir das listas locais.
///
/// Limites `null` = ilimitado (premium).
@immutable
class PlanStatus {
  final bool isPremium;
  final int? maxGroups;
  final int? maxSubscriptions;
  final int? monthlyCharges;
  final bool allowInterest;
  final bool allowAutoCharge;
  final int activeGroups;
  final int activeSubscriptions;
  final int chargesThisMonth;

  const PlanStatus({
    required this.isPremium,
    required this.maxGroups,
    required this.maxSubscriptions,
    required this.monthlyCharges,
    required this.allowInterest,
    required this.allowAutoCharge,
    required this.activeGroups,
    required this.activeSubscriptions,
    required this.chargesThisMonth,
  });

  bool get canCreateGroup => maxGroups == null || activeGroups < maxGroups!;
  bool get canCreateSubscription =>
      maxSubscriptions == null || activeSubscriptions < maxSubscriptions!;
  bool get canSendCharge =>
      monthlyCharges == null || chargesThisMonth < monthlyCharges!;

  int? get remainingGroups =>
      maxGroups == null ? null : (maxGroups! - activeGroups).clamp(0, 1 << 30);
  int? get remainingSubscriptions => maxSubscriptions == null
      ? null
      : (maxSubscriptions! - activeSubscriptions).clamp(0, 1 << 30);

  factory PlanStatus.fromRpc(Map<String, dynamic> json) {
    final limits = (json['limits'] as Map?)?.cast<String, dynamic>() ?? const {};
    final usage = (json['usage'] as Map?)?.cast<String, dynamic>() ?? const {};
    int? asInt(dynamic v) => v == null ? null : (v as num).toInt();
    return PlanStatus(
      isPremium: json['is_premium'] as bool? ?? false,
      maxGroups: asInt(limits['max_groups']),
      maxSubscriptions: asInt(limits['max_subscriptions']),
      monthlyCharges: asInt(limits['monthly_charges']),
      allowInterest: limits['allow_interest'] as bool? ?? false,
      allowAutoCharge: limits['allow_auto_charge'] as bool? ?? false,
      activeGroups: asInt(usage['active_groups']) ?? 0,
      activeSubscriptions: asInt(usage['active_subscriptions']) ?? 0,
      chargesThisMonth: asInt(usage['charges_this_month']) ?? 0,
    );
  }

  /// Plano free com os limites padrão (usado no mock e como fallback). Os
  /// números batem com a tabela `plan_limits` da migração 20260721170000.
  factory PlanStatus.free({
    int activeGroups = 0,
    int activeSubscriptions = 0,
    int chargesThisMonth = 0,
  }) =>
      PlanStatus(
        isPremium: false,
        maxGroups: 3,
        maxSubscriptions: 2,
        monthlyCharges: 30,
        allowInterest: false,
        allowAutoCharge: false,
        activeGroups: activeGroups,
        activeSubscriptions: activeSubscriptions,
        chargesThisMonth: chargesThisMonth,
      );
}
