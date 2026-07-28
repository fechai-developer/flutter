import 'package:flutter/material.dart';

/// Corte de onda (wave-cut) na borda inferior — elemento de assinatura visual
/// do Fechaí (ver DESIGN_SYSTEM.md). Não existe pronto no Flutter, então é um
/// CustomClipper. Usado **só** em cards de saldo/cobrança, nunca em todo card.
///
/// A onda é uma sequência de curvas de Bézier suaves na base do retângulo,
/// reforçando a metáfora de água/fluidez do dinheiro circulando.
class WaveClipper extends CustomClipper<Path> {
  /// Altura da ondulação em px.
  final double amplitude;

  /// Quantos "vales" a onda tem ao longo da largura.
  final int waves;

  const WaveClipper({this.amplitude = 14, this.waves = 3});

  @override
  Path getClip(Size size) {
    final path = Path()
      ..lineTo(0, size.height - amplitude)
      ..lineTo(0, size.height - amplitude);

    final waveWidth = size.width / waves;
    for (int i = 0; i < waves; i++) {
      final startX = waveWidth * i;
      final midX = startX + waveWidth / 2;
      final endX = startX + waveWidth;
      // vale no meio de cada segmento, cristas nas junções
      path.quadraticBezierTo(
        midX,
        size.height + amplitude,
        endX,
        size.height - amplitude,
      );
    }

    path
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant WaveClipper oldClipper) =>
      oldClipper.amplitude != amplitude || oldClipper.waves != waves;
}
