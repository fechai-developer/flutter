import 'package:flutter/material.dart';

import '../icons.dart';
import '../../theme/app_theme.dart';
import '../limits.dart';
import 'premium.dart';

/// Slider de juros por atraso (0–20% a.m.) com enquadramento ilustrativo (#10).
/// Usado em grupos (#8) e assinaturas.
///
/// Quando [locked] (recurso premium indisponível no plano free), o controle
/// aparece **desabilitado** com selo Premium e um convite para assinar — a
/// trava dura fica no banco (`enforce_group_rules`/`enforce_subscription_rules`).
class InterestSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final bool locked;

  const InterestSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (locked) return _LockedInterest(theme: theme);

    final warn = value > InterestPolicy.warnAbovePct;
    final accent = warn ? AppColors.coralAceso : AppColors.verdeAguaProfundo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Juros por atraso', style: theme.textTheme.labelLarge),
            const Spacer(),
            Text('${value.toStringAsFixed(1)}% ao mês',
                style: AppTheme.moneyStyle(fontSize: 16, color: accent)),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: InterestPolicy.maxPct,
          divisions: (InterestPolicy.maxPct * 2).toInt(), // passos de 0,5%
          activeColor: accent,
          label: '${value.toStringAsFixed(1)}%',
          onChanged: onChanged,
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: warn
                ? AppColors.coralAceso.withValues(alpha: 0.1)
                : AppColors.mentaViva.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(warn ? Icons.warning_amber_rounded : Icons.info_outline, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(child: Text(InterestPolicy.helperText(value), style: theme.textTheme.bodySmall)),
            ],
          ),
        ),
      ],
    );
  }
}

class _LockedInterest extends StatelessWidget {
  final ThemeData theme;
  const _LockedInterest({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Juros por atraso',
                style: theme.textTheme.labelLarge?.copyWith(color: AppColors.textoSuave)),
            const Spacer(),
            PremiumChip(onTap: () => PremiumUpsell.show(context, highlight: 'juros')),
          ],
        ),
        // Slider "fantasma" — desabilitado, só para dar a dica do controle.
        IgnorePointer(
          child: Opacity(
            opacity: 0.4,
            child: Slider(
              value: 0,
              min: 0,
              max: InterestPolicy.maxPct,
              onChanged: (_) {},
            ),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => PremiumUpsell.show(context, highlight: 'juros'),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.areiaNeutra,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.lock, size: 18, color: AppColors.verdeAguaProfundo),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Definir juros por atraso é um recurso Premium. '
                    'No plano grátis a cobrança sai sem juros. Toque para conhecer.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
