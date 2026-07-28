import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'wave_clipper.dart';

/// Card de assinatura visual do Fechaí: cantos generosos + corte de onda na
/// base + gradiente Verde-água → Menta. Reservado para saldo/cobrança
/// (DESIGN_SYSTEM.md) — não usar como card genérico.
class WaveCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final double waveAmplitude;

  const WaveCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 34),
    this.gradient,
    this.waveAmplitude = 14,
  });

  /// Gradiente de saldo — o único lugar do app que espalha o gradiente
  /// (DESIGN_SYSTEM.md: "só atrás do número de saldo total").
  static const Gradient balanceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.verdeAguaProfundo, Color(0xFF17A78F), AppColors.mentaViva],
    stops: [0.0, 0.6, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: WaveClipper(amplitude: waveAmplitude),
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient ?? balanceGradient,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        padding: padding,
        width: double.infinity,
        child: child,
      ),
    );
  }
}
