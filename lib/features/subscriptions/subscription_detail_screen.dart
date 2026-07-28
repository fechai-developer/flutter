import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/icons.dart';

import 'package:uuid/uuid.dart';

import '../../core/utils/currency.dart';
import '../../core/utils/masks.dart';
import '../../core/utils/whatsapp.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/member_name.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/sheet_handle.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/wave_card.dart';
import '../../data/models/person.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';
import '../charge/charge_sheet.dart';
import 'edit_subscription_sheet.dart';

class SubscriptionDetailScreen extends ConsumerWidget {
  final String subscriptionId;
  const SubscriptionDetailScreen({super.key, required this.subscriptionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionByIdProvider(subscriptionId));
    final me = ref.watch(currentUserProvider).valueOrNull;

    return sub.when(
      skipLoadingOnReload: true, // não pisca ao rebuscar por evento de realtime
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Erro: $e'))),
      data: (s) => Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: Icon(AppIcons.arrowLeft), onPressed: () => context.go('/subscriptions')),
          title: Row(
            children: [
              Text(s.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Flexible(child: Text(s.serviceName, overflow: TextOverflow.ellipsis)),
            ],
          ),
          actions: [
            if (s.ownerId == 'me' && !s.viewerRemoved)
              IconButton(
                icon: Icon(AppIcons.pencilSimple),
                tooltip: 'Editar assinatura',
                onPressed: () => showEditSubscriptionSheet(context, s),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if (s.viewerRemoved) ...[
              _RemovedSubBanner(),
              const SizedBox(height: 12),
            ],
            // Card de resumo do ciclo (gradiente + onda)
            WaveCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('A receber neste ciclo',
                      style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text(Money.format(s.pendingThisCycle),
                      style: AppTheme.moneyStyle(fontSize: 36, color: Colors.white)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _Chip(icon: AppIconsFill.calendarBlank, label: 'Vence dia ${s.billingDay}'),
                      const SizedBox(width: 10),
                      _Chip(icon: AppIconsFill.coins, label: '${Money.format(s.quotaValue)}/cota'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Juros por atraso (aviso de teto legal)
            if (s.monthlyInterestPct > 0)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.coralAceso.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  border: Border.all(color: AppColors.coralAceso.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(AppIcons.percent, color: AppColors.coralAceso),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Juros de ${s.monthlyInterestPct.toStringAsFixed(1)}% ao mês sobre atrasos.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Valor ilustrativo combinado entre vocês. O Fechaí não cobra nem processa pagamentos.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: 'Os juros ajudam a incentivar o pagamento em dia. '
                          'São definidos pelo dono da conta/assinatura e têm caráter ilustrativo — '
                          'o app apenas organiza a conta, não é uma instituição de cobrança.',
                      triggerMode: TooltipTriggerMode.tap,
                      showDuration: const Duration(seconds: 6),
                      child: Icon(AppIcons.info, size: 18, color: AppColors.coralAceso),
                    ),
                  ],
                ),
              ),

            Row(
              children: [
                Text('Participantes', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                Text('${s.filledQuotas}/${s.quotaCount}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),

            // Você primeiro, depois em ordem alfabética (Etapa C). Só ativos.
            for (final m in _orderedMembers(s))
              _MemberRow(
                sub: s,
                member: m,
                isOwner: s.ownerId == 'me',
                mePixKey: me?.pixKey ?? '',
                meName: me?.name ?? 'Você',
                onRemove: (s.ownerId == 'me' && m.person.id != 'me' && !s.viewerRemoved)
                    ? () => _removeParticipant(context, ref, s, m)
                    : null,
                onCharge: () async {
                  final paid = await showChargeSheet(
                    context,
                    ChargeRequest(
                      fromName: me?.name ?? 'Você',
                      fromPixKey: me?.pixKey ?? '',
                      toName: m.person.name,
                      toLastName: m.person.lastName,
                      toPhone: m.person.phone,
                      amount: m.amountDue(s.monthlyInterestPct),
                      reason: '${s.serviceName} — dia ${s.billingDay}',
                    ),
                  );
                  if (paid == true) {
                    await ref.read(repositoryControllerProvider)
                        .setQuotaStatus(s.id, m.person.id, QuotaStatus.paid);
                  }
                },
                onToggle: () => ref.read(repositoryControllerProvider).setQuotaStatus(
                      s.id,
                      m.person.id,
                      m.status == QuotaStatus.paid ? QuotaStatus.pending : QuotaStatus.paid,
                    ),
              ),

            if (s.openQuotas > 0 && !s.viewerRemoved) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _addParticipant(context, ref, s),
                icon: Icon(AppIcons.plus, size: 18),
                label: Text('Adicionar participante (${s.openQuotas} vaga(s))'),
              ),
            ],

            // Ex-participantes (removidos, histórico preservado).
            if (_removedMembers(s).isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Ex-participantes', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              for (final m in _removedMembers(s))
                Opacity(
                  opacity: 0.6,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        MemberAvatar(name: m.person.name, lastName: m.person.lastName, size: 34),
                        const SizedBox(width: 10),
                        Expanded(child: Text(m.person.fullName, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        StatusChip.archived(),
                      ],
                    ),
                  ),
                ),
            ],

            // Sair da assinatura (participante não-dono, ainda ativo).
            if (s.ownerId != 'me' && !s.viewerRemoved) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _leaveSubscription(context, ref, s),
                  icon: Icon(AppIcons.signOut, size: 18, color: AppColors.coralAceso),
                  label: Text('Sair da assinatura', style: TextStyle(color: AppColors.coralAceso)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addParticipant(BuildContext context, WidgetRef ref, Subscription s) async {
    final nameCtrl = TextEditingController();
    final lastNameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 8),
              Text('Novo participante', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Cota de ${Money.format(s.quotaValue)}/mês', style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nome'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: lastNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Sobrenome'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [BrPhoneInputFormatter()],
                decoration: const InputDecoration(labelText: 'Celular', hintText: '(11) 99999-8888'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final n = nameCtrl.text.trim();
                    if (n.isEmpty) return;
                    if (isReservedName(n)) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('"Você" é reservado — use o nome da pessoa.')),
                      );
                      return;
                    }
                    Navigator.of(ctx).pop(true);
                  },
                  child: const Text('Adicionar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (added == true) {
      await ref.read(repositoryControllerProvider).addSubscriptionMember(
            s.id,
            SubscriptionMember(
              person: Person(
                id: const Uuid().v4(),
                name: nameCtrl.text.trim(),
                lastName: lastNameCtrl.text.trim().isEmpty ? null : lastNameCtrl.text.trim(),
                phone: digitsOf(phoneCtrl.text),
              ),
              quota: double.parse(s.quotaValue.toStringAsFixed(2)),
              status: QuotaStatus.pending,
            ),
          );
    }
    nameCtrl.dispose();
    lastNameCtrl.dispose();
    phoneCtrl.dispose();
  }

  Future<void> _removeParticipant(
      BuildContext context, WidgetRef ref, Subscription s, SubscriptionMember m) async {
    // Pré-checagem de UX: quem aceitou precisa estar com a cota quitada.
    if (m.inviteAccepted && (m.status != QuotaStatus.paid || m.monthsLate > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${m.person.name} tem cota em aberto. Quite antes de remover.')),
      );
      return;
    }
    final keepsHistory = m.inviteAccepted;
    try {
      await ref.read(repositoryControllerProvider).removeSubscriptionMember(s.id, m.person.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${m.person.name} tem cota em aberto. Quite antes de remover.')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(keepsHistory
          ? '${m.person.name} foi removido. Ainda vê o histórico da assinatura.'
          : '${m.person.name} foi removido da assinatura.'),
    ));
  }

  Future<void> _leaveSubscription(BuildContext context, WidgetRef ref, Subscription s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da assinatura?'),
        content: Text('Você vai sair de "${s.serviceName}". Se já participou, continua '
            'com acesso somente ao histórico.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.coralAceso),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repositoryControllerProvider).removeSubscriptionMember(s.id, 'me');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Você tem cota em aberto. Quite antes de sair.')),
        );
      }
      return;
    }
    if (context.mounted) context.go('/subscriptions');
  }
}

/// Participantes ATIVOS: você primeiro; os demais em ordem alfabética. A
/// não-aceitação é sinalizada pela tag de status (Etapa C). Removidos vão para
/// a subseção "Ex-participantes".
List<SubscriptionMember> _orderedMembers(Subscription s) {
  final active = s.members.where((m) => !m.removed);
  final others = active.where((m) => m.person.id != 'me').toList()
    ..sort((a, b) => a.person.name.toLowerCase().compareTo(b.person.name.toLowerCase()));
  return [
    ...active.where((m) => m.person.id == 'me'),
    ...others,
  ];
}

/// Ex-participantes (removidos, com histórico preservado), em ordem alfabética.
List<SubscriptionMember> _removedMembers(Subscription s) =>
    s.members.where((m) => m.removed).toList()
      ..sort((a, b) => a.person.name.toLowerCase().compareTo(b.person.name.toLowerCase()));

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Aviso quando o usuário logado foi removido da assinatura (acesso leitura).
class _RemovedSubBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.areiaNeutra.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.lock, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Você não faz mais parte desta assinatura. Aqui fica só o histórico.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final Subscription sub;
  final SubscriptionMember member;
  final bool isOwner;
  final String mePixKey;
  final String meName;
  final VoidCallback onCharge;
  final VoidCallback onToggle;
  /// Remover participante (só o dono, e não a si mesmo). Null esconde a ação.
  final VoidCallback? onRemove;

  const _MemberRow({
    required this.sub,
    required this.member,
    required this.isOwner,
    required this.mePixKey,
    required this.meName,
    required this.onCharge,
    required this.onToggle,
    this.onRemove,
  });

  Future<void> _inviteWhatsApp(BuildContext context) async {
    final ok = await WhatsApp.send(
      phone: member.person.phone,
      message: WhatsApp.inviteMessage(
        toName: member.person.name.split(' ').first,
        contextName: sub.serviceName,
        isGroup: false,
      ),
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não consegui abrir o WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = member.person.id == 'me';
    final inviteStatus = isMe ? MemberStatus.accepted : member.inviteStatus;
    final paid = member.status == QuotaStatus.paid;
    final overdue = member.status == QuotaStatus.overdue;
    final interest = member.interest(sub.monthlyInterestPct);

    Color statusColor;
    String statusLabel;
    switch (member.status) {
      case QuotaStatus.paid:
        statusColor = AppColors.verdeAguaProfundo;
        statusLabel = 'Pago';
        break;
      case QuotaStatus.overdue:
        statusColor = AppColors.coralAceso;
        statusLabel = 'Em atraso';
        break;
      case QuotaStatus.pending:
        statusColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
        statusLabel = 'Pendente';
        break;
    }

    return DeclinedDim(
      declined: inviteStatus == MemberStatus.declined,
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: overdue ? AppColors.coralAceso.withValues(alpha: 0.4) : AppColors.areiaNeutra),
      ),
      child: Row(
        children: [
          MemberAvatar(name: member.person.name, lastName: isMe ? null : member.person.lastName, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: MemberName(
                        isMe ? 'Você' : member.person.fullName,
                        status: inviteStatus,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                      ),
                    ),
                    if (!isMe) MemberStatusChip(inviteStatus),
                  ],
                ),
                Row(
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(statusLabel, style: theme.textTheme.bodySmall?.copyWith(color: statusColor)),
                    if (interest > 0) ...[
                      const SizedBox(width: 6),
                      Text('+ ${Money.format(interest)} juros',
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.coralAceso)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(member.amountDue(sub.monthlyInterestPct), fontSize: 15),
              const SizedBox(height: 4),
              // Enquanto não aceita o convite, não se cobra (regra de negócio:
              // a cobrança só sai depois do aceite). Oferecemos convidar. (Etapa C)
              if (isOwner && !isMe && inviteStatus != MemberStatus.accepted)
                InkWell(
                  onTap: () => _inviteWhatsApp(context),
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.verdeAguaProfundo, borderRadius: BorderRadius.circular(100)),
                    child: const Text('Convidar', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                )
              else if (isOwner && !isMe && !paid) ...[
                InkWell(
                  onTap: onCharge,
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.coralAceso, borderRadius: BorderRadius.circular(100)),
                    child: const Text('Cobra Aí', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 4),
                // Confirmar que o participante pagou (caso tenha esquecido). (#1)
                InkWell(
                  onTap: onToggle,
                  child: Text('Já recebi', style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.verdeAguaProfundo, fontWeight: FontWeight.w600)),
                ),
              ]
              else if (isOwner && !isMe && paid)
                InkWell(
                  onTap: onToggle,
                  child: Text('desfazer', style: theme.textTheme.bodySmall),
                ),
            ],
          ),
          if (onRemove != null)
            IconButton(
              tooltip: inviteStatus != MemberStatus.accepted ? 'Cancelar convite' : 'Remover',
              onPressed: onRemove,
              icon: Icon(AppIcons.trash, size: 18, color: AppColors.coralAceso),
            ),
        ],
      ),
      ),
    );
  }
}
