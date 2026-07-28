import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/icons.dart';

import '../../core/utils/currency.dart';
import '../../core/utils/pix.dart';
import '../../core/utils/whatsapp.dart';
import '../../core/widgets/expandable_tile.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/pix_qr.dart';
import '../../core/widgets/sheet_handle.dart';
import '../../theme/app_theme.dart';

/// Dados necessários para montar uma cobrança "Cobra Aí".
class ChargeRequest {
  final String fromName; // quem cobra (usuário) — primeiro nome
  final String fromPixKey; // chave PIX do recebedor
  final String toName; // quem paga — primeiro nome
  final String? toLastName; // sobrenome do pagador (iniciais do avatar + nome completo)
  final String? toPhone; // telefone do pagador (para o wa.me)
  final double amount;
  final String reason; // "Praia de Maresias", "Netflix — julho"...

  const ChargeRequest({
    required this.fromName,
    required this.fromPixKey,
    required this.toName,
    this.toLastName,
    this.toPhone,
    required this.amount,
    required this.reason,
  });

  /// "Nome Sobrenome" do pagador (só o primeiro nome quando não há sobrenome).
  String get toFullName {
    final l = toLastName?.trim() ?? '';
    return l.isEmpty ? toName : '$toName $l';
  }
}

/// Abre a folha de cobrança. Retorna `true` se o usuário marcou como pago.
Future<bool?> showChargeSheet(BuildContext context, ChargeRequest request) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ChargeSheet(request: request),
  );
}

class _ChargeSheet extends StatefulWidget {
  final ChargeRequest request;
  const _ChargeSheet({required this.request});

  @override
  State<_ChargeSheet> createState() => _ChargeSheetState();
}

class _ChargeSheetState extends State<_ChargeSheet> {
  bool _copied = false;
  bool _sent = false;

  String get _pixCode => PixPayload.build(
        pixKey: widget.request.fromPixKey,
        merchantName: widget.request.fromName,
        merchantCity: 'SAO PAULO',
        amount: widget.request.amount,
      );

  String get _message => WhatsApp.chargeMessage(
        fromName: widget.request.fromName,
        toName: widget.request.toName,
        amountLabel: Money.format(widget.request.amount),
        reason: widget.request.reason,
        pixCode: _pixCode,
      );

  Future<void> _copyPix() async {
    await Clipboard.setData(ClipboardData(text: _pixCode));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código PIX copiado ✅'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _sendWhatsApp() async {
    final ok = await WhatsApp.send(message: _message, phone: widget.request.toPhone);
    if (!mounted) return;
    if (ok) {
      setState(() => _sent = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o WhatsApp')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
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
                  MemberAvatar(name: r.toName, lastName: r.toLastName, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cobrar ${r.toFullName}', style: theme.textTheme.titleLarge),
                        Text(r.reason, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  Money.format(r.amount),
                  style: AppTheme.moneyStyle(fontSize: 40, color: AppColors.coralAceso),
                ),
              ),
              const SizedBox(height: 20),

              // Ações em destaque primeiro (#2): confirmar recebimento + cobrar.
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.verdeAguaProfundo),
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: Icon(AppIcons.check, size: 22),
                  label: Text(
                    _sent ? 'Já recebi' : 'Já recebi (marcar pago)',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _sendWhatsApp,
                  icon: Icon(AppIconsFill.whatsappLogo, size: 22),
                  label: const Text('Cobra Aí no WhatsApp'),
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),

              // PIX copia e cola — o que aparece de cara (é o que se paga).
              Text('PIX copia e cola', style: theme.textTheme.labelLarge),
              const SizedBox(height: 10),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _copyPix,
                  icon: Icon(_copied ? AppIconsFill.checkCircle : AppIcons.copy, size: 20),
                  label: Text(_copied ? 'PIX copiado' : 'Copiar PIX copia e cola'),
                ),
              ),
              const SizedBox(height: 12),

              // QR e mensagem ficam escondidos em gavetas.
              ExpandableTile(
                title: 'Mostrar seu QR Code PIX para recebimento',
                icon: AppIcons.qrCode,
                child: PixQr(data: _pixCode),
              ),
              const SizedBox(height: 10),
              ExpandableTile(
                title: 'Ver mensagem da cobrança',
                icon: AppIconsFill.whatsappLogo,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.areiaNeutra),
                  ),
                  child: Text(_message, style: theme.textTheme.bodyMedium),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
