import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../theme/app_theme.dart';

/// QR Code de um payload PIX, na moldura branca padrão do app. Reutilizado nas
/// folhas de cobrança (meu QR p/ receber) e pagamento (QR do recebedor p/ escanear).
class PixQr extends StatelessWidget {
  final String data;
  final double size;
  const PixQr({super.key, required this.data, this.size = 180});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: AppColors.areiaNeutra),
        ),
        child: QrImageView(
          data: data,
          version: QrVersions.auto,
          size: size,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: AppColors.tintaProfunda),
          dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.circle, color: AppColors.tintaProfunda),
        ),
      ),
    );
  }
}
