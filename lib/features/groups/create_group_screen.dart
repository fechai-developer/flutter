import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/masks.dart';
import '../../core/widgets/emoji_picker.dart';
import '../../core/widgets/interest_slider.dart';
import '../../core/widgets/known_members_picker.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/premium.dart';
import '../../data/models/person.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _memberNameController = TextEditingController();
  final _memberLastNameController = TextEditingController();
  final _memberPhoneController = TextEditingController();
  final _uuid = const Uuid();

  String _emoji = '🏖️';
  final List<Person> _members = [];
  double _interest = 0;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _memberNameController.dispose();
    _memberLastNameController.dispose();
    _memberPhoneController.dispose();
    super.dispose();
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
    final last = _memberLastNameController.text.trim();
    setState(() {
      _members.add(Person(
        id: _uuid.v4(),
        name: name,
        lastName: last.isEmpty ? null : last,
        phone: _memberPhoneController.text.replaceAll(RegExp(r'\D'), ''),
      ));
      _memberNameController.clear();
      _memberLastNameController.clear();
      _memberPhoneController.clear();
    });
  }

  Future<void> _create() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dê um nome à conta')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final g = await ref.read(repositoryControllerProvider).createGroup(
            name: _nameController.text.trim(),
            emoji: _emoji,
            members: _members,
            monthlyInterestPct: _interest,
          );
      if (!mounted) return;
      context.go('/groups/${g.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível criar a conta: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = ref.watch(planStatusProvider).valueOrNull;
    final allowInterest = plan?.allowInterest ?? false;
    final atGroupLimit = plan != null && !plan.canCreateGroup;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: Icon(AppIcons.arrowLeft), onPressed: () => context.go('/groups')),
        title: const Text('Nova conta'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Ícone', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          EmojiPicker(value: _emoji, onChanged: (e) => setState(() => _emoji = e)),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Nome da conta', hintText: 'Praia de Maresias'),
          ),
          const SizedBox(height: 28),
          Text('Membros', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Você já entra automaticamente. Adicione o resto do pessoal.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          KnownMembersPicker(
            added: _members,
            onPick: (p) => setState(() => _members.add(p)),
          ),
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
          _MemberChip(name: 'Você (organizador)', removable: false),
          for (final m in _members)
            _MemberChip(
              name: m.fullName,
              lastName: m.lastName,
              subtitle: formatPhone(m.phone),
              onRemove: () => setState(() => _members.remove(m)),
            ),
          const SizedBox(height: 24),
          InterestSlider(
            value: _interest,
            locked: !allowInterest,
            onChanged: (v) => setState(() => _interest = v),
          ),
          const SizedBox(height: 28),
          if (atGroupLimit) ...[
            PremiumLockBanner(
              title: 'Limite de contas ativas atingido',
              message: 'Seu plano permite ${plan.maxGroups} contas ativas ao mesmo tempo. '
                  'Arquive uma conta encerrada ou assine o Premium para criar mais.',
            ),
            const SizedBox(height: 16),
          ],
          ElevatedButton(
            onPressed: (_saving || atGroupLimit) ? null : _create,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Criar conta'),
          ),
        ],
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  final String name;
  final String? lastName;
  final String? subtitle;
  final bool removable;
  final VoidCallback? onRemove;
  const _MemberChip({required this.name, this.lastName, this.subtitle, this.removable = true, this.onRemove});

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
