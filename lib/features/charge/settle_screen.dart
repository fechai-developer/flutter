import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/utils/consolidated_balance.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/pix.dart';
import '../../core/utils/whatsapp.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/user_name.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';
import 'charge_sheet.dart';
import 'pay_sheet.dart';

/// Tela "Acertar" — consolida, pessoa a pessoa, tudo o que me devem e tudo o
/// que devo, somando grupos + assinaturas. Permite quitar com uma pessoa de uma
/// vez só (atualiza todos os grupos/assinaturas envolvidos). Cobrar/Pagar são
/// ações desta tela.
class SettleScreen extends ConsumerWidget {
  const SettleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groups = ref.watch(groupsProvider);
    final subs = ref.watch(subscriptionsProvider);

    final people = ConsolidatedBalances.compute(
      groups.valueOrNull ?? const [],
      subs.valueOrNull ?? const [],
    );

    final toReceive = people.fold<double>(0, (a, p) => a + (p.net > 0 ? p.net : 0));
    final toPay = people.fold<double>(0, (a, p) => a + (p.net < 0 ? -p.net : 0));
    final me = ref.watch(currentUserProvider).valueOrNull;
    final creditors = people.where((p) => p.net > 0).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Acertar')),
      floatingActionButton: creditors.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab_charge_all',
              backgroundColor: AppColors.coralAceso,
              foregroundColor: Colors.white,
              onPressed: () => _chargeAll(context, creditors, me?.name ?? 'Você', me?.pixKey ?? ''),
              icon: Icon(AppIconsFill.whatsappLogo, size: 20),
              label: Text('Cobrar tudo (${creditors.length})'),
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(groupsProvider);
          ref.invalidate(subscriptionsProvider);
        },
        child: (groups.isLoading || subs.isLoading)
            ? const Center(child: CircularProgressIndicator())
            : people.isEmpty
                ? const _EmptyState()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _SummaryCard(toReceive: toReceive, toPay: toPay),
                      const SizedBox(height: 24),
                      Text('Pessoa a pessoa', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('Tudo somado de contas e assinaturas. Acerte de uma vez só.',
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 12),
                      for (final pb in people) _PersonRow(balance: pb),
                    ],
                  ),
      ),
    );
  }

  /// Cobra de uma vez todo mundo que me deve (net > 0). Dispara um WhatsApp por
  /// pessoa com o total consolidado e o PIX copia e cola.
  Future<void> _chargeAll(BuildContext context, List<PersonBalance> creditors, String meName, String mePixKey) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cobrar tudo?'),
        content: Text('Vamos abrir o WhatsApp para cada uma das ${creditors.length} pessoas que te devem, com o total já somado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cobrar tudo')),
        ],
      ),
    );
    if (ok != true) return;

    for (final pb in creditors) {
      final reason = pb.count == 1 ? pb.items.first.sourceName : 'Acerto geral (${pb.count} contas)';
      final pix = PixPayload.build(
        pixKey: mePixKey,
        merchantName: meName,
        merchantCity: 'SAO PAULO',
        amount: pb.net,
      );
      final msg = WhatsApp.chargeMessage(
        fromName: meName,
        toName: pb.person.name,
        amountLabel: Money.format(pb.net),
        reason: reason,
        pixCode: pix,
      );
      await WhatsApp.send(message: msg, phone: pb.person.phone);
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final double toReceive;
  final double toPay;
  const _SummaryCard({required this.toReceive, required this.toPay});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.areiaNeutra),
        boxShadow: AppTheme.softShadow(),
      ),
      child: Row(
        children: [
          Expanded(child: _stat(context, 'A receber', toReceive, AppColors.verdeAguaProfundo, AppIconsFill.arrowDown)),
          Container(width: 1, height: 40, color: AppColors.areiaNeutra),
          Expanded(child: _stat(context, 'A pagar', toPay, AppColors.coralAceso, AppIconsFill.arrowUp)),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, double value, Color color, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 4),
        MoneyText(value, fontSize: 20, color: color),
      ],
    );
  }
}

class _PersonRow extends ConsumerWidget {
  final PersonBalance balance;
  const _PersonRow({required this.balance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final net = balance.net;
    final theyOwe = net > 0;
    final color = theyOwe ? AppColors.verdeAguaProfundo : AppColors.coralAceso;
    final origins = balance.count;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          onTap: () => _openSheet(context, ref),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: balance.hasOverdue ? AppColors.coralAceso.withValues(alpha: 0.4) : AppColors.areiaNeutra),
            ),
            child: Row(
              children: [
                MemberAvatar.person(balance.person, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UserName(balance.person.name, style: theme.textTheme.titleMedium, maxLines: 1),
                      Row(
                        children: [
                          if (balance.hasOverdue) ...[
                            Icon(AppIconsFill.warningCircle, size: 13, color: AppColors.coralAceso),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            '${theyOwe ? 'te deve' : 'você deve'} · $origins ${origins == 1 ? 'pendência' : 'pendências'}',
                            style: theme.textTheme.bodySmall?.copyWith(color: balance.hasOverdue ? AppColors.coralAceso : null),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(net.abs(), fontSize: 16, color: color),
                    const SizedBox(height: 2),
                    Icon(AppIcons.caretRight, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PersonSheet(balance: balance),
    );
  }
}

/// Detalhe do saldo com uma pessoa: quebra por grupo/assinatura + ações de
/// cobrar/pagar e "acertar tudo de uma vez".
class _PersonSheet extends ConsumerWidget {
  final PersonBalance balance;
  const _PersonSheet({required this.balance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final theyOweMe = balance.theyOweMe;
    final iOweThem = balance.iOweThem;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44, height: 5,
                decoration: BoxDecoration(color: AppColors.areiaNeutra, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                MemberAvatar.person(balance.person, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(balance.person.name, style: theme.textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        balance.net > 0
                            ? 'te deve ${Money.format(balance.net)} no total'
                            : 'você deve ${Money.format(balance.net.abs())} no total',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Pendências', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final it in balance.items) _ItemLine(item: it),
            const SizedBox(height: 20),

            // Ações
            if (theyOweMe > 0.009) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final paid = await showChargeSheet(
                      context,
                      ChargeRequest(
                        fromName: me?.name ?? 'Você',
                        fromPixKey: me?.pixKey ?? '',
                        toName: balance.person.name,
                        toLastName: balance.person.lastName,
                        toPhone: balance.person.phone,
                        amount: theyOweMe,
                        reason: _reason(),
                      ),
                    );
                    if (paid == true) {
                      await _settle(ref, theyOweMe: true);
                      if (context.mounted) _done(context, 'Recebimento de ${balance.person.name} registrado ✅');
                    }
                  },
                  icon: Icon(AppIconsFill.whatsappLogo, size: 20),
                  label: Text('Cobra Aí — ${Money.format(theyOweMe)}'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await _settle(ref, theyOweMe: true);
                    if (context.mounted) _done(context, 'Tudo o que ${balance.person.name} te devia foi acertado ✅');
                  },
                  child: const Text('Já recebi tudo'),
                ),
              ),
            ],

            if (iOweThem > 0.009) ...[
              if (theyOweMe > 0.009) const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.verdeAguaProfundo),
                  onPressed: () async {
                    final paid = await showPaySheet(
                      context,
                      PayRequest(
                        toName: balance.person.name,
                        toLastName: balance.person.lastName,
                        toPixKey: balance.person.pixKey,
                        amount: iOweThem,
                        reason: _reason(),
                      ),
                    );
                    if (paid == true) {
                      await _settle(ref, theyOweMe: false);
                      if (context.mounted) _done(context, 'Pagamento para ${balance.person.name} registrado ✅');
                    }
                  },
                  icon: Icon(AppIcons.qrCode, size: 20),
                  label: Text('Pagar — ${Money.format(iOweThem)}'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await _settle(ref, theyOweMe: false);
                    if (context.mounted) _done(context, 'Tudo o que você devia a ${balance.person.name} foi acertado ✅');
                  },
                  child: const Text('Já paguei tudo'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _reason() {
    final names = <String>{for (final i in balance.items) i.sourceName}.toList();
    if (names.length == 1) return names.first;
    return 'Acerto geral (${names.length} contas)';
  }

  /// Acerta todas as pendências de uma direção com esta pessoa, de uma vez —
  /// registrando o acerto em cada grupo e marcando as cotas de assinatura.
  Future<void> _settle(WidgetRef ref, {required bool theyOweMe}) async {
    final c = ref.read(repositoryControllerProvider);
    for (final it in balance.items.where((i) => i.theyOweMe == theyOweMe)) {
      if (it.isSubscription) {
        await c.setQuotaStatus(it.sourceId, it.quotaPersonId!, QuotaStatus.paid);
      } else {
        await c.settleUp(
          it.sourceId,
          fromId: it.theyOweMe ? it.otherId : 'me',
          toId: it.theyOweMe ? 'me' : it.otherId,
          amount: it.amount,
        );
      }
    }
  }

  void _done(BuildContext context, String msg) {
    // Captura o messenger ANTES do pop — depois o context da folha fica defunto.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

class _ItemLine extends StatelessWidget {
  final DebtItem item;
  const _ItemLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = item.theyOweMe ? AppColors.verdeAguaProfundo : AppColors.coralAceso;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: AppColors.mentaViva.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(item.isSubscription ? AppIcons.repeat : AppIcons.usersThree, size: 17, color: AppColors.verdeAguaProfundo),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.sourceName, style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${item.isSubscription ? 'Assinatura' : 'Conta'} · ${item.theyOweMe ? 'te deve' : 'você deve'}${item.overdue ? ' · atrasado' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(color: item.overdue ? AppColors.coralAceso : null),
                ),
              ],
            ),
          ),
          MoneyText(item.amount, fontSize: 14, color: color),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.checkCircle, size: 64, color: AppColors.mentaViva),
            const SizedBox(height: 16),
            Text('Tudo quitado 🎉', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Quando houver saldo com alguém — em contas ou\nassinaturas — aparece aqui pra acertar de uma vez.',
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
