import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/icons.dart';

import 'package:uuid/uuid.dart';

import '../../core/categories.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/masks.dart';
import '../../core/widgets/category_picker.dart';
import '../../core/widgets/emoji_picker.dart';
import '../../core/widgets/interest_slider.dart';
import '../../core/widgets/known_members_picker.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/premium.dart';
import '../../data/models/person.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';

class CreateSubscriptionScreen extends ConsumerStatefulWidget {
  const CreateSubscriptionScreen({super.key});

  @override
  ConsumerState<CreateSubscriptionScreen> createState() => _CreateSubscriptionScreenState();
}

class _CreateSubscriptionScreenState extends ConsumerState<CreateSubscriptionScreen> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _memberNameController = TextEditingController();
  final _memberLastNameController = TextEditingController();
  final _memberPhoneController = TextEditingController();
  final _uuid = const Uuid();
  final List<Person> _members = [];
  String _emoji = '🎬';
  int _billingDay = 15;
  int _quotaCount = 4;
  double _interest = 0;
  String? _category;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _memberNameController.dispose();
    _memberLastNameController.dispose();
    _memberPhoneController.dispose();
    super.dispose();
  }

  /// Você ocupa 1 cota; sobram [_quotaCount] - 1 para participantes.
  bool get _hasFreeQuota => _members.length < _quotaCount - 1;

  void _pickMember(Person p) {
    if (!_hasFreeQuota) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem cotas livres. Aumente o número de cotas.')),
      );
      return;
    }
    setState(() => _members.add(p));
  }

  void _addMember() {
    final name = _memberNameController.text.trim();
    if (name.isEmpty) return;
    if (isReservedName(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('"Você" é reservado — use o nome da pessoa.')),
      );
      return;
    }
    if (!_hasFreeQuota) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem cotas livres. Aumente o número de cotas.')),
      );
      return;
    }
    final last = _memberLastNameController.text.trim();
    setState(() {
      _members.add(Person(
        id: _uuid.v4(),
        name: name,
        lastName: last.isEmpty ? null : last,
        phone: digitsOf(_memberPhoneController.text),
      ));
      _memberNameController.clear();
      _memberLastNameController.clear();
      _memberPhoneController.clear();
    });
  }

  double get _quotaValue {
    final total = Money.parse(_amountController.text) ?? 0;
    return _quotaCount == 0 ? 0 : total / _quotaCount;
  }

  Future<void> _create() async {
    final total = Money.parse(_amountController.text);
    if (_nameController.text.trim().isEmpty || total == null || total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha nome e valor total')),
      );
      return;
    }
    setState(() => _saving = true);
    final me = ref.read(currentUserProvider).valueOrNull;
    final quota = double.parse((total / _quotaCount).toStringAsFixed(2));
    final sub = Subscription(
      id: '',
      serviceName: _nameController.text.trim(),
      emoji: _emoji,
      totalAmount: total,
      billingDay: _billingDay,
      quotaCount: _quotaCount,
      monthlyInterestPct: _interest,
      category: _category,
      ownerId: 'me',
      members: [
        if (me != null)
          SubscriptionMember(person: me, quota: quota, status: QuotaStatus.paid),
        // Participantes entram como convite pendente (Etapa C).
        for (final m in _members.take(_quotaCount - 1))
          SubscriptionMember(
            person: m,
            quota: quota,
            status: QuotaStatus.pending,
            inviteStatus: MemberStatus.pending,
          ),
      ],
    );
    try {
      final created = await ref.read(repositoryControllerProvider).createSubscription(sub);
      if (!mounted) return;
      context.go('/subscriptions/${created.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível criar a assinatura: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = ref.watch(planStatusProvider).valueOrNull;
    final allowInterest = plan?.allowInterest ?? false;
    final atSubLimit = plan != null && !plan.canCreateSubscription;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: Icon(AppIcons.arrowLeft), onPressed: () => context.go('/subscriptions')),
        title: const Text('Nova assinatura'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Ícone', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          EmojiPicker(
            value: _emoji,
            presets: EmojiPicker.subscriptionEmojis,
            onChanged: (e) => setState(() => _emoji = e),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Serviço', hintText: 'Netflix, Spotify, Microsoft 365...'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Valor total do plano', prefixText: r'R$ '),
          ),
          const SizedBox(height: 20),
          Text('Tipo', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          CategoryPicker(
            categories: kSubscriptionCategories,
            value: _category,
            history: ref.watch(usedSubscriptionCategoriesProvider),
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 24),

          // Dia de cobrança
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
                final selected = day == _billingDay;
                return GestureDetector(
                  onTap: () => setState(() => _billingDay = day),
                  child: Container(
                    width: 44,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.verdeAguaProfundo : theme.cardTheme.color,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? AppColors.verdeAguaProfundo : AppColors.areiaNeutra),
                    ),
                    alignment: Alignment.center,
                    child: Text('$day',
                        style: TextStyle(
                          color: selected ? Colors.white : theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Nº de cotas
          Text('Número de cotas', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
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
                    Text('${Money.format(_quotaValue)} por pessoa', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton.outlined(
                onPressed: () => setState(() => _quotaCount++),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Participantes (Etapa C) — iguais à criação de grupo: conhecidos + manual.
          Text('Participantes', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Você já ocupa 1 cota. Convide quem divide as outras ${_quotaCount - 1}.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          KnownMembersPicker(added: _members, onPick: _pickMember),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _memberNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _memberLastNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Sobrenome'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _memberPhoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [BrPhoneInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Celular', hintText: '(11) 9...'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _addMember,
                style: IconButton.styleFrom(backgroundColor: AppColors.verdeAguaProfundo),
                icon: Icon(AppIcons.plus, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CreateMemberRow(name: 'Você (organizador)', removable: false),
          for (final m in _members)
            _CreateMemberRow(
              name: m.fullName,
              lastName: m.lastName,
              subtitle: formatPhone(m.phone),
              onRemove: () => setState(() => _members.remove(m)),
            ),
          const SizedBox(height: 24),

          // Juros por atraso — enquadramento ilustrativo (#10)
          InterestSlider(
            value: _interest,
            locked: !allowInterest,
            onChanged: (v) => setState(() => _interest = v),
          ),
          const SizedBox(height: 28),
          if (atSubLimit) ...[
            PremiumLockBanner(
              title: 'Limite de assinaturas ativas atingido',
              message: 'Seu plano permite ${plan.maxSubscriptions} assinaturas ativas ao mesmo tempo. '
                  'Arquive uma assinatura encerrada ou assine o Premium para adicionar mais.',
            ),
            const SizedBox(height: 16),
          ],
          ElevatedButton(
            onPressed: (_saving || atSubLimit) ? null : _create,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Criar assinatura'),
          ),
        ],
      ),
    );
  }
}

/// Linha de participante já adicionado na criação da assinatura.
class _CreateMemberRow extends StatelessWidget {
  final String name;
  final String? lastName;
  final String? subtitle;
  final bool removable;
  final VoidCallback? onRemove;
  const _CreateMemberRow({required this.name, this.lastName, this.subtitle, this.removable = true, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          MemberAvatar(name: name, lastName: lastName, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (removable)
            IconButton(
              onPressed: onRemove,
              icon: Icon(AppIcons.trash, size: 18, color: AppColors.coralAceso),
            ),
        ],
      ),
    );
  }
}
