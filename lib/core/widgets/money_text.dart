import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../utils/currency.dart';

/// Exibe valores em R$ sempre com [AppTheme.moneyStyle] (números tabulares) —
/// nunca com o TextTheme padrão (convenção do CLAUDE.md).
///
/// Opcionalmente colore por sinal: verde-menta para crédito (a receber),
/// coral para débito (a pagar/atraso).
class MoneyText extends StatelessWidget {
  final double value;
  final double fontSize;
  final Color? color;
  final bool signed;

  const MoneyText(
    this.value, {
    super.key,
    this.fontSize = 28,
    this.color,
    this.signed = false,
  });

  /// Colore automaticamente por sinal: positivo = a receber, negativo = a pagar.
  const MoneyText.byBalance(
    this.value, {
    super.key,
    this.fontSize = 28,
  })  : color = null,
        signed = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color resolved;
    if (color != null) {
      resolved = color!;
    } else if (signed && value < 0) {
      resolved = AppColors.coralAceso;
    } else if (signed && value > 0) {
      resolved = isDark ? AppColors.mentaVivaDark : AppColors.verdeAguaProfundo;
    } else {
      resolved = isDark ? AppColors.nevoaClaraDarkText : AppColors.tintaProfunda;
    }

    final label = signed && value > 0
        ? '+${Money.format(value)}'
        : Money.format(value);

    return Text(
      label,
      style: AppTheme.moneyStyle(fontSize: fontSize, color: resolved),
    );
  }
}
