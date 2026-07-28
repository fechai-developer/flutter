import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../icons.dart';

/// Marca do Fechaí (#12): a onda-assinatura (água/fluidez) com uma moeda "R$"
/// — dinheiro que circula/flui entre as pessoas. Une a identidade visual do
/// design system à leitura imediata de "dinheiro".
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 88});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.29;
    final coin = size * 0.4;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Base: quadrado com gradiente água + onda
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.verdeAguaProfundo, AppColors.mentaViva],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(radius),
            ),
            alignment: Alignment.center,
            child: Icon(AppIconsFill.waveSine, size: size * 0.52, color: Colors.white),
          ),
          // Moeda R$ "caindo" na água — no canto inferior direito
          Positioned(
            right: -coin * 0.18,
            bottom: -coin * 0.18,
            child: Container(
              width: coin,
              height: coin,
              decoration: BoxDecoration(
                color: AppColors.coralAceso,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: size * 0.03),
              ),
              alignment: Alignment.center,
              child: Text(
                r'R$',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: coin * 0.42,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
