import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/icons.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/pix.dart';
import '../../core/widgets/expandable_tile.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/pix_qr.dart';
import '../../core/widgets/sheet_handle.dart';
import '../../theme/app_theme.dart';

/// Dados para pagar alguém (#7). O recebedor é quem tem a chave PIX.
class PayRequest {
  final String toName; // quem recebe — primeiro nome
  final String? toLastName; // sobrenome (só para as iniciais do avatar)
  final String? toPixKey; // chave PIX do recebedor
  final double amount;
  final String reason;

  const PayRequest({
    required this.toName,
    this.toLastName,
    required this.toPixKey,
    required this.amount,
    required this.reason,
  });
}

/// Abre a folha de pagamento. Retorna `true` se o usuário marcou como pago.
Future<bool?> showPaySheet(BuildContext context, PayRequest request) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaySheet(request: request),
  );
}

class _PaySheet extends StatelessWidget {
  final PayRequest request;
  const _PaySheet({required this.request});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasKey = (request.toPixKey ?? '').trim().isNotEmpty;
    final pixCode = hasKey
        ? PixPayload.build(
            pixKey: request.toPixKey!,
            merchantName: request.toName,
            merchantCity: 'SAO PAULO',
            amount: request.amount,
          )
        : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              const SheetHandle(),
              const SizedBox(height: 20),
              Row(
                children: [
                  MemberAvatar(name: request.toName, lastName: request.toLastName, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pagar ${request.toName}', style: theme.textTheme.titleLarge),
                        Text(request.reason, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  Money.format(request.amount),
                  style: AppTheme.moneyStyle(fontSize: 40, color: AppColors.verdeAguaProfundo),
                ),
              ),
              const SizedBox(height: 20),

              // Ação principal em destaque: confirmar que já pagou (#2).
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.verdeAguaProfundo),
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: Icon(AppIcons.check, size: 22),
                  label: const Text('Já paguei', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'O acerto é registrado para os dois lados. O Fechaí não processa o pagamento — '
                'ele acontece direto no seu banco.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),

              // Como pagar (PIX) — depois da confirmação.
              Text('Como pagar', style: theme.textTheme.labelLarge),
              const SizedBox(height: 10),
              if (!hasKey)
                _NoKey(name: request.toName)
              else ...[
                _KeyRow(label: 'Chave PIX', value: request.toPixKey!),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: pixCode!));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PIX copia e cola copiado ✅'), behavior: SnackBarBehavior.floating),
                        );
                      }
                    },
                    icon: Icon(AppIcons.copy, size: 20),
                    label: const Text('Copiar PIX copia e cola'),
                  ),
                ),
                const SizedBox(height: 12),
                // QR do recebedor numa gaveta — abra para escanear apontando a
                // câmera do seu banco para a tela.
                ExpandableTile(
                  title: 'Ver QR Code de ${request.toName} para escanear',
                  icon: AppIcons.qrCode,
                  child: PixQr(data: pixCode!),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _KeyRow extends StatelessWidget {
  final String label;
  final String value;
  const _KeyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Row(
        children: [
          Icon(AppIcons.qrCode, size: 20, color: AppColors.verdeAguaProfundo),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(value, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chave copiada ✅'), behavior: SnackBarBehavior.floating),
                );
              }
            },
            icon: Icon(AppIcons.copy, size: 18),
          ),
        ],
      ),
    );
  }
}

class _NoKey extends StatelessWidget {
  final String name;
  const _NoKey({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.coralAceso.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.coralAceso.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.warningCircle, color: AppColors.coralAceso),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$name ainda não cadastrou uma chave PIX. Combine o pagamento por outro meio '
              'ou peça pra pessoa adicionar a chave no perfil.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
