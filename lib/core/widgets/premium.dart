import 'package:flutter/material.dart';

import '../icons.dart';
import '../../theme/app_theme.dart';

/// Elementos de UI do freemium (gating comercial).
///
/// Padrão visual: gradiente verde-água (identidade) + acento menta + faísca.
/// O checkout real do Premium ainda não existe (Fase 2 do roadmap) — por ora o
/// CTA abre uma folha explicativa e sinaliza "em breve". Ao ligar o pagamento,
/// basta trocar [PremiumUpsell._onSubscribe].

/// Benefícios do Premium mostrados na folha de upsell.
const List<String> kPremiumBenefits = [
  'Mais contas e assinaturas ativas ao mesmo tempo',
  'Juros por atraso configuráveis nas contas e assinaturas',
  'Cobra Aí sem limite mensal',
  'Cobrança automática (lembretes em D+3, D+10, D+30…)',
  'Relatórios e exportação',
];

/// Selo "Premium" — pílula pequena com faísca. Use ao lado de um recurso travado.
class PremiumChip extends StatelessWidget {
  final VoidCallback? onTap;
  const PremiumChip({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.verdeAguaProfundo, Color(0xFF17A78F)],
        ),
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIconsFill.sparkle, size: 13, color: AppColors.mentaViva),
          const SizedBox(width: 5),
          const Text('Premium',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      onTap: onTap,
      child: chip,
    );
  }
}

/// Banner de recurso travado / limite atingido, com CTA para o Premium.
/// Ex.: limite de grupos ativos, cobrança acima do teto mensal.
class PremiumLockBanner extends StatelessWidget {
  final String title;
  final String message;
  const PremiumLockBanner({super.key, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.mentaViva.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.verdeAguaProfundo.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.lock, size: 18, color: AppColors.verdeAguaProfundo),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              const PremiumChip(),
            ],
          ),
          const SizedBox(height: 8),
          Text(message, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => PremiumUpsell.show(context),
              icon: Icon(AppIconsFill.sparkle, size: 18),
              label: const Text('Assinar o Premium'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Folha de upsell do Premium: lista de benefícios + CTA de assinatura.
class PremiumUpsell {
  const PremiumUpsell._();

  static Future<void> show(BuildContext context, {String? highlight}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PremiumSheet(highlight: highlight),
    );
  }
}

class _PremiumSheet extends StatelessWidget {
  final String? highlight;
  const _PremiumSheet({this.highlight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.verdeAguaProfundo, Color(0xFF17A78F)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(AppIconsFill.sparkle, color: AppColors.mentaViva, size: 26),
              const SizedBox(width: 10),
              Text('Fechaí Premium',
                  style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Desbloqueie os recursos que fazem a cobrança fluir sozinha.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 18),
          for (final b in kPremiumBenefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    highlight != null && b.toLowerCase().contains(highlight!.toLowerCase())
                        ? AppIconsFill.sparkle
                        : AppIcons.checkCircle,
                    color: AppColors.mentaViva,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(b,
                        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.verdeAguaProfundo,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Assinatura do Premium chega na próxima etapa.')),
                );
              },
              child: const Text('Quero ser Premium'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Agora não', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
  }
}
