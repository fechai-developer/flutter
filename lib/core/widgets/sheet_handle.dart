import 'package:flutter/material.dart';

import '../icons.dart';
import '../../theme/app_theme.dart';

/// Cabeçalho padrão de bottom sheet: alça central + um **X cinza** no canto
/// superior direito para fechar. Tocar fora também fecha, mas o X é a pista
/// visual óbvia de "dá pra sair daqui".
///
/// [onClose] permite um comportamento próprio (ex.: descartar rascunho);
/// por padrão faz `Navigator.maybePop()` — que, em sheets que retornam valor,
/// equivale a cancelar (retorna null).
class SheetHandle extends StatelessWidget {
  final VoidCallback? onClose;
  const SheetHandle({super.key, this.onClose});

  @override
  Widget build(BuildContext context) {
    final grip = Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(color: AppColors.areiaNeutra, borderRadius: BorderRadius.circular(3)),
    );
    return Row(
      children: [
        const SizedBox(width: 40), // equilibra o X à direita → alça fica centralizada
        Expanded(child: Center(child: grip)),
        SizedBox(
          width: 40,
          child: IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: 'Fechar',
            onPressed: onClose ?? () => Navigator.of(context).maybePop(),
            icon: Icon(
              AppIcons.close,
              size: 22,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
  }
}
