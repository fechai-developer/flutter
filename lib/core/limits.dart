/// Limites e enquadramento de juros por atraso (#10).
///
/// Decisão de produto: os juros são **ilustrativos**, para gestão informal de
/// despesas pessoais entre as pessoas do grupo. O app não é instituição de
/// pagamento nem plataforma de cobrança (ver termo de uso aceito no login).
class InterestPolicy {
  InterestPolicy._();

  /// Teto permitido no slider.
  static const double maxPct = 20.0;

  /// Acima disso, o aviso fica em vermelho (#3). Mantido baixo de propósito.
  static const double warnAbovePct = 1.0;

  static String helperText(double pct) {
    if (pct <= 0) {
      return 'Sem juros. Você pode definir uma taxa ilustrativa para incentivar o pagamento em dia.';
    }
    if (pct > warnAbovePct) {
      return 'Acima de ${warnAbovePct.toStringAsFixed(0)}% ao mês costuma ser considerado alto. '
          'Lembre: é uma taxa ilustrativa combinada entre vocês, não uma cobrança formal — '
          'o app só ajuda a organizar.';
    }
    return 'Taxa ilustrativa de ${pct.toStringAsFixed(1)}% ao mês, combinada entre as pessoas envolvidas.';
  }

  /// Acréscimo de juros simples sobre um valor em atraso (#2).
  /// [base] valor original, [pct] juros ao mês, [monthsLate] meses de atraso.
  static double accrue(double base, double pct, int monthsLate) {
    if (pct <= 0 || monthsLate <= 0) return base;
    final withInterest = base * (1 + (pct / 100) * monthsLate);
    return double.parse(withInterest.toStringAsFixed(2));
  }

  /// Só o valor dos juros (para exibir "+ R$ x de juros").
  static double interestOnly(double base, double pct, int monthsLate) =>
      double.parse((accrue(base, pct, monthsLate) - base).toStringAsFixed(2));
}
