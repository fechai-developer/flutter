import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/currency.dart';
import '../../core/widgets/emoji_picker.dart';
import '../../core/widgets/interest_slider.dart';
import '../../core/widgets/sheet_handle.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';

/// Editar assinatura (#2): serviço, emoji, valor, dia de cobrança, cotas, juros.
Future<void> showEditSubscriptionSheet(BuildContext context, Subscription s) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EditSubscriptionSheet(subscription: s),
  );
}

class EditSubscriptionSheet extends ConsumerStatefulWidget {
  final Subscription subscription;
  const EditSubscriptionSheet({super.key, required this.subscription});

  @override
  ConsumerState<EditSubscriptionSheet> createState() => _EditSubscriptionSheetState();
}

class _EditSubscriptionSheetState extends ConsumerState<EditSubscriptionSheet> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late String _emoji;
  late int _billingDay;
  late int _quotaCount;
  late double _interest;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.subscription;
    _name = TextEditingController(text: s.serviceName);
    _amount = TextEditingController(text: Money.plain(s.totalAmount));
    _emoji = s.emoji;
    _billingDay = s.billingDay;
    _quotaCount = s.quotaCount;
    _interest = s.monthlyInterestPct;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final total = Money.parse(_amount.text);
    if (_name.text.trim().isEmpty || total == null || total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha nome e valor')));
      return;
    }
    if (_quotaCount < widget.subscription.members.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Já há ${widget.subscription.members.length} participantes; aumente as cotas.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(repositoryControllerProvider).updateSubscription(
            widget.subscription.id,
            serviceName: _name.text.trim(),
            emoji: _emoji,
            totalAmount: total,
            billingDay: _billingDay,
            quotaCount: _quotaCount,
            monthlyInterestPct: _interest,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = Money.parse(_amount.text) ?? 0;
    final quotaValue = _quotaCount == 0 ? 0 : total / _quotaCount;
    final allowInterest = ref.watch(planStatusProvider).valueOrNull?.allowInterest ?? false;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 20),
              Text('Editar assinatura', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              EmojiPicker(
                value: _emoji,
                presets: EmojiPicker.subscriptionEmojis,
                onChanged: (e) => setState(() => _emoji = e),
              ),
              const SizedBox(height: 16),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Serviço')),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Valor total', prefixText: r'R$ '),
              ),
              const SizedBox(height: 20),
              Text('Dia de cobrança', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 31,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final day = i + 1;
                    final sel = day == _billingDay;
                    return GestureDetector(
                      onTap: () => setState(() => _billingDay = day),
                      child: Container(
                        width: 44,
                        decoration: BoxDecoration(
                          color: sel ? AppColors.verdeAguaProfundo : theme.cardTheme.color,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: sel ? AppColors.verdeAguaProfundo : AppColors.areiaNeutra),
                        ),
                        alignment: Alignment.center,
                        child: Text('$day', style: TextStyle(color: sel ? Colors.white : theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Text('Número de cotas', style: theme.textTheme.labelLarge),
              Row(
                children: [
                  IconButton.outlined(
                    onPressed: _quotaCount > 1 ? () => setState(() => _quotaCount--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text('$_quotaCount', style: theme.textTheme.displaySmall),
                        Text('${Money.format(quotaValue.toDouble())} por pessoa', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton.outlined(onPressed: () => setState(() => _quotaCount++), icon: const Icon(Icons.add)),
                ],
              ),
              const SizedBox(height: 20),
              InterestSlider(
                value: _interest,
                locked: !allowInterest,
                onChanged: (v) => setState(() => _interest = v),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Salvar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
