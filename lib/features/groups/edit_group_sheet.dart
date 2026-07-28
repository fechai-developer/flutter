import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/icons.dart';
import '../../core/utils/balance.dart';
import '../../core/utils/masks.dart';
import '../../core/utils/whatsapp.dart';
import '../../core/widgets/emoji_picker.dart';
import '../../core/widgets/interest_slider.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/member_name.dart';
import '../../core/widgets/sheet_handle.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models/expense_group.dart';
import '../../data/models/person.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';

/// Editar grupo (#4): renomear, trocar emoji, ajustar juros, add/remover
/// membros. Aplica as mudanças direto via RepositoryController.
Future<void> showEditGroupSheet(BuildContext context, WidgetRef ref, ExpenseGroup group) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EditGroupSheet(group: group),
  );
}

class EditGroupSheet extends ConsumerStatefulWidget {
  final ExpenseGroup group;
  const EditGroupSheet({super.key, required this.group});

  @override
  ConsumerState<EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends ConsumerState<EditGroupSheet> {
  late final TextEditingController _nameController;
  final _memberNameController = TextEditingController();
  final _memberLastNameController = TextEditingController();
  final _memberPhoneController = TextEditingController();
  final _uuid = const Uuid();

  late String _emoji;
  late double _interest;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _emoji = widget.group.emoji;
    _interest = widget.group.monthlyInterestPct;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _memberNameController.dispose();
    _memberLastNameController.dispose();
    _memberPhoneController.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    final name = _memberNameController.text.trim();
    if (name.isEmpty) return;
    if (isReservedName(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('"Você" é reservado — use o nome da pessoa.')),
      );
      return;
    }
    final last = _memberLastNameController.text.trim();
    await ref.read(repositoryControllerProvider).addMember(
          widget.group.id,
          Person(
            id: _uuid.v4(),
            name: name,
            lastName: last.isEmpty ? null : last,
            phone: _memberPhoneController.text.replaceAll(RegExp(r'\D'), ''),
          ),
        );
    _memberNameController.clear();
    _memberLastNameController.clear();
    _memberPhoneController.clear();
  }

  /// Membros ATIVOS: você primeiro; os demais em ordem alfabética. A
  /// não-aceitação é sinalizada pela tag de status (Etapa C). Ex-membros
  /// (removidos) saem daqui e vão para a subseção "Ex-participantes".
  List<Person> _sortedMembers(ExpenseGroup group) {
    final active = group.members.where((m) => !group.isRemoved(m.id));
    final others = active.where((m) => m.id != 'me').toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [
      ...active.where((m) => m.id == 'me'),
      ...others,
    ];
  }

  /// Ex-participantes (removidos, com histórico preservado), em ordem alfabética.
  List<Person> _removedMembers(ExpenseGroup group) =>
      group.members.where((m) => group.isRemoved(m.id)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<void> _inviteWhatsApp(Person m) async {
    final ok = await WhatsApp.send(
      phone: m.phone,
      message: WhatsApp.inviteMessage(
        toName: m.name.split(' ').first,
        contextName: widget.group.name,
        isGroup: true,
      ),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não consegui abrir o WhatsApp.')),
      );
    }
  }

  Future<void> _removeMember(ExpenseGroup group, Person m) async {
    // Pré-checagem de UX: só remove quem está zerado (o servidor também trava).
    final balance = BalanceCalculator.netBalances(group)[m.id] ?? 0;
    if (balance.abs() > 0.009) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${m.name} ainda tem saldo na conta. Acerte antes de remover.')),
      );
      return;
    }
    // Já teve movimentação? → some do ativo mas mantém o histórico (soft).
    final keepsHistory = group.expenses.any((e) =>
            e.paidByPersonId == m.id || e.shares.containsKey(m.id)) ||
        group.payments.any((p) => p.fromId == m.id || p.toId == m.id);
    try {
      await ref.read(repositoryControllerProvider).removeMember(group.id, m.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${m.name} ainda tem saldo na conta. Acerte antes de remover.')),
        );
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(keepsHistory
          ? '${m.name} foi removido. Ainda vê o histórico das despesas em que participou.'
          : '${m.name} foi removido da conta.'),
    ));
  }

  Future<void> _leaveGroup(ExpenseGroup group) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: Text('Você vai sair de "${group.name}". Se já participou de despesas, '
            'continua com acesso somente ao histórico delas.'),
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
      await ref.read(repositoryControllerProvider).removeMember(group.id, 'me');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Você ainda tem saldo na conta. Acerte antes de sair.')),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // fecha a folha
    context.go('/groups');
  }

  Future<void> _confirmDelete() async {
    final g = ref.read(groupByIdProvider(widget.group.id)).valueOrNull ?? widget.group;
    final hasData = g.expenses.isNotEmpty || g.payments.isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir conta?'),
        content: Text(hasData
            ? 'A conta "${g.name}" tem lançamentos. Excluir apaga tudo para todos os membros. Esta ação não pode ser desfeita.'
            : 'A conta "${g.name}" será excluída. Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.coralAceso),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(repositoryControllerProvider).deleteGroup(widget.group.id);
    if (!mounted) return;
    Navigator.of(context).pop(); // fecha a folha
    context.go('/groups');
  }

  Future<void> _saveMeta() async {
    setState(() => _saving = true);
    await ref.read(repositoryControllerProvider).updateGroup(
          widget.group.id,
          name: _nameController.text.trim(),
          emoji: _emoji,
          monthlyInterestPct: _interest,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Reobtém o grupo atualizado (membros mudam ao add/remover sem fechar).
    final group = ref.watch(groupByIdProvider(widget.group.id)).valueOrNull ?? widget.group;
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
              Text('Editar conta', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              EmojiPicker(value: _emoji, onChanged: (e) => setState(() => _emoji = e)),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome da conta'),
              ),
              const SizedBox(height: 20),
              InterestSlider(
                value: _interest,
                locked: !allowInterest,
                onChanged: (v) => setState(() => _interest = v),
              ),
              const SizedBox(height: 20),
              Text('Membros', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              // Você primeiro, depois em ordem alfabética (Etapa C).
              for (final m in _sortedMembers(group))
                DeclinedDim(
                  declined: group.isDeclined(m.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        MemberAvatar(name: m.name, lastName: m.id == 'me' ? null : m.lastName, size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: MemberName(
                            m.id == 'me' ? 'Você' : m.fullName,
                            status: group.statusOf(m.id),
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                          ),
                        ),
                        MemberStatusChip(group.statusOf(m.id)),
                        if (m.id != 'me' && group.notAccepted(m.id))
                          IconButton(
                            tooltip: 'Convidar pelo WhatsApp',
                            onPressed: () => _inviteWhatsApp(m),
                            icon: Icon(AppIcons.whatsappLogo, size: 18, color: AppColors.verdeAguaProfundo),
                          ),
                        if (m.id != 'me')
                          IconButton(
                            tooltip: group.notAccepted(m.id) ? 'Cancelar convite' : 'Remover da conta',
                            onPressed: () => _removeMember(group, m),
                            icon: Icon(AppIcons.trash, size: 18, color: AppColors.coralAceso),
                          ),
                      ],
                    ),
                  ),
                ),
              // Ex-participantes: removidos, mas com histórico preservado.
              if (_removedMembers(group).isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Ex-participantes', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                for (final m in _removedMembers(group))
                  Opacity(
                    opacity: 0.6,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          MemberAvatar(name: m.name, lastName: m.lastName, size: 34),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(m.fullName, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          StatusChip.archived(),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
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
                      decoration: const InputDecoration(labelText: 'Celular'),
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
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveMeta,
                  child: const Text('Salvar'),
                ),
              ),
              if (group.isOwner) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _saving ? null : _confirmDelete,
                    icon: Icon(AppIcons.trash, size: 18, color: AppColors.coralAceso),
                    label: Text('Excluir conta', style: TextStyle(color: AppColors.coralAceso)),
                  ),
                ),
              ] else ...[
                // Membro não-dono pode sair (mesmas travas: só zerado; mantém
                // histórico se já participou de despesas).
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _saving ? null : () => _leaveGroup(group),
                    icon: Icon(AppIcons.signOut, size: 18, color: AppColors.coralAceso),
                    label: Text('Sair da conta', style: TextStyle(color: AppColors.coralAceso)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
