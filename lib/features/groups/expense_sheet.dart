import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/icons.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/sheet_handle.dart';
import '../../data/models/expense.dart';
import '../../data/models/expense_group.dart';
import '../../theme/app_theme.dart';

/// Resultado da folha de despesa: salvar (add/edit) ou excluir.
class ExpenseSheetResult {
  final Expense? expense;
  final bool deleted;
  const ExpenseSheetResult.save(this.expense) : deleted = false;
  const ExpenseSheetResult.remove()
      : expense = null,
        deleted = true;
}

/// Abre a folha de despesa. Passe [existing] para editar. `#5` e `#6`.
Future<ExpenseSheetResult?> showExpenseSheet(
  BuildContext context, {
  required ExpenseGroup group,
  Expense? existing,
}) {
  return showModalBottomSheet<ExpenseSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ExpenseSheet(group: group, existing: existing),
  );
}

class ExpenseSheet extends StatefulWidget {
  final ExpenseGroup group;
  final Expense? existing;
  const ExpenseSheet({super.key, required this.group, this.existing});

  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  late final TextEditingController _descController;
  late final TextEditingController _amountController;
  late String _paidBy;
  late SplitType _type;
  late Set<String> _participants;
  bool _recurring = false;
  DateTime? _recurrenceUntil;
  late int _recurrenceDay;

  /// Inputs por pessoa para %, partes e valor exato.
  final Map<String, TextEditingController> _inputs = {};

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _descController = TextEditingController(text: e?.description ?? '');
    _amountController =
        TextEditingController(text: e != null ? Money.plain(e.amount) : '');
    // Só membros ATIVOS entram no seletor/rateio — quem saiu do grupo não pode
    // ser selecionado nem continuar numa despesa recorrente (a próxima ocorrência
    // é redividida entre quem ficou). O dono só confere e salva pra confirmar.
    final active = widget.group.activeMembers;
    // Quem pagou: se quem pagava saiu (payerLeft), cai em "Você" (ou 1º ativo).
    final rawPaidBy = e?.paidByPersonId;
    _paidBy = (rawPaidBy != null && !widget.group.isRemoved(rawPaidBy))
        ? rawPaidBy
        : (active.any((m) => m.id == 'me') ? 'me' : (active.isNotEmpty ? active.first.id : 'me'));
    _type = e?.type ?? SplitType.equal;
    _recurring = e?.isRecurring ?? false;
    _recurrenceUntil = e?.recurrenceUntil;
    // Dia da recorrência: usa o salvo; senão o dia do lançamento (limitado a 27).
    _recurrenceDay = e?.recurrenceDay ?? (e?.date ?? DateTime(2026, 7, 20)).day.clamp(1, 27);
    // Ao editar, tira do rateio quem foi removido → rebalanceia entre os ativos.
    _participants = e != null
        ? e.shares.keys.where((id) => !widget.group.isRemoved(id)).toSet()
        : active.map((m) => m.id).toSet();

    // Ao EDITAR, repreenche os campos por pessoa a partir dos shares salvos —
    // senão a soma zera e o botão Salvar trava (bug). Vale p/ todos os tipos
    // que usam input (exato, partes e porcentagem); "igual" não usa campo.
    for (final m in active) {
      String initial = '';
      if (e != null && e.shares.containsKey(m.id)) {
        final share = e.shares[m.id]!;
        if (e.type == SplitType.exact || e.type == SplitType.weight) {
          // Exato: o próprio valor. Partes: pesos são relativos, então usar o
          // valor (R$) como peso reproduz a mesma proporção ao recalcular.
          initial = Money.plain(share);
        } else if (e.type == SplitType.percentage) {
          // % = fatia / total × 100 (precisão extra p/ a soma fechar ~100
          // dentro da tolerância de validação).
          initial = _pctText(e.amount > 0 ? share / e.amount * 100 : 0);
        }
      }
      _inputs[m.id] = TextEditingController(text: initial);
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    _amountController.dispose();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _amount => Money.parse(_amountController.text) ?? 0;

  double _input(String id) => Money.parse(_inputs[id]?.text ?? '') ?? 0;

  Map<String, double> get _rawInputs =>
      {for (final id in _participants) id: _input(id)};

  /// Shares calculados ao vivo para preview.
  Map<String, double> get _previewShares => computeShares(
        amount: _amount,
        type: _type,
        participantIds: _participants.toList(),
        inputs: _rawInputs,
      );

  /// Mensagem de validação da soma (null = ok).
  String? get _splitError {
    if (_participants.isEmpty) return 'Selecione ao menos uma pessoa';
    switch (_type) {
      case SplitType.equal:
        return null;
      case SplitType.percentage:
        final sum = _rawInputs.values.fold<double>(0, (a, b) => a + b);
        final diff = double.parse((100 - sum).toStringAsFixed(2));
        if (diff.abs() < 0.01) return null;
        return diff > 0 ? 'Faltam ${diff.toStringAsFixed(1)}%' : 'Passou ${(-diff).toStringAsFixed(1)}%';
      case SplitType.weight:
        final sum = _rawInputs.values.fold<double>(0, (a, b) => a + b);
        return sum > 0 ? null : 'Defina as partes de cada um';
      case SplitType.exact:
        final sum = _rawInputs.values.fold<double>(0, (a, b) => a + b);
        final diff = double.parse((_amount - sum).toStringAsFixed(2));
        if (diff.abs() < 0.01) return null;
        return diff > 0 ? 'Faltam ${Money.format(diff)}' : 'Passou ${Money.format(-diff)}';
    }
  }

  bool get _canSave =>
      _descController.text.trim().isNotEmpty && _amount > 0 && _splitError == null;

  void _save() {
    final expense = Expense.create(
      id: widget.existing?.id ??
          'e_${DateTime(2026, 7, 20).microsecondsSinceEpoch}_${_descController.text.hashCode}',
      description: _descController.text.trim(),
      amount: _amount,
      paidByPersonId: _paidBy,
      type: _type,
      participantIds: _participants.toList(),
      inputs: _rawInputs,
      date: widget.existing?.date ?? DateTime(2026, 7, 20),
      recurrence: _recurring ? Recurrence.monthly : Recurrence.none,
      recurrenceUntil: _recurring ? _recurrenceUntil : null,
      recurrenceDay: _recurring ? _recurrenceDay : null,
      // Preserva o vínculo de ocorrência gerada (senão editar orfanaria a linha
      // e a geração recriaria aquele mês, duplicando).
      recurrenceParentId: widget.existing?.recurrenceParentId,
      occurrencePeriod: widget.existing?.occurrencePeriod,
    );
    Navigator.of(context).pop(ExpenseSheetResult.save(expense));
  }

  Future<void> _pickUntil() async {
    final now = DateTime(2026, 7, 20);
    final picked = await showDatePicker(
      context: context,
      initialDate: _recurrenceUntil ?? DateTime(now.year, now.month + 3, now.day),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      helpText: 'Repetir até',
    );
    if (picked != null) setState(() => _recurrenceUntil = picked);
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir despesa?'),
        content: Text('"${widget.existing!.description}" será removida da conta.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop(const ExpenseSheetResult.remove());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = widget.group.activeMembers;
    final preview = _previewShares;
    final error = _splitError;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(_isEdit ? 'Editar despesa' : 'Nova despesa', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  if (_isEdit)
                    IconButton(
                      onPressed: _confirmDelete,
                      icon: Icon(AppIcons.trash, color: AppColors.coralAceso),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.existing?.needsRecurrenceReview ?? false) ...[
                _ReviewNotice(review: widget.existing!.recurrenceReview),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _descController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Descrição', hintText: 'Mercado, Uber, aluguel...'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Valor', prefixText: r'R$ '),
              ),
              const SizedBox(height: 20),
              Text('Quem pagou', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in members)
                    ChoiceChip(
                      label: Text(m.id == 'me' ? 'Você' : m.fullName),
                      selected: _paidBy == m.id,
                      onSelected: (_) => setState(() => _paidBy = m.id),
                      selectedColor: AppColors.mentaViva.withValues(alpha: 0.4),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // Seletor de tipo de divisão (estilo Splitwise)
              Text('Como dividir', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              _SplitTypeSelector(
                selected: _type,
                onChanged: (t) => setState(() => _type = t),
              ),
              const SizedBox(height: 6),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(AppIcons.warningCircle, size: 15, color: AppColors.coralAceso),
                      const SizedBox(width: 6),
                      Text(error, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.coralAceso)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),

              for (final m in members)
                _ParticipantRow(
                  name: m.id == 'me' ? 'Você' : m.fullName,
                  avatarName: m.name,
                  avatarLastName: m.id == 'me' ? null : m.lastName,
                  selected: _participants.contains(m.id),
                  type: _type,
                  inputController: _inputs[m.id]!,
                  shareLabel: _participants.contains(m.id) ? Money.format(preview[m.id] ?? 0) : null,
                  onToggle: (v) => setState(() {
                    if (v) {
                      _participants.add(m.id);
                    } else {
                      _participants.remove(m.id);
                    }
                  }),
                  onInputChanged: () => setState(() {}),
                ),

              const SizedBox(height: 12),
              // Recorrência (#2)
              Material(
                color: theme.cardTheme.color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.areiaNeutra),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _recurring,
                      activeThumbColor: AppColors.verdeAguaProfundo,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                      title: const Text('Despesa recorrente'),
                      subtitle: Text(
                        _recurring ? 'Repete todo mês no dia $_recurrenceDay' : 'Repete todo mês num dia fixo',
                        style: theme.textTheme.bodySmall,
                      ),
                      onChanged: (v) => setState(() => _recurring = v),
                    ),
                    if (_recurring) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Dia do mês', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 44,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: 27,
                                separatorBuilder: (_, _) => const SizedBox(width: 8),
                                itemBuilder: (context, i) {
                                  final day = i + 1;
                                  final selected = day == _recurrenceDay;
                                  return GestureDetector(
                                    onTap: () => setState(() => _recurrenceDay = day),
                                    child: Container(
                                      width: 44,
                                      decoration: BoxDecoration(
                                        color: selected ? AppColors.verdeAguaProfundo : theme.cardTheme.color,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: selected ? AppColors.verdeAguaProfundo : AppColors.areiaNeutra),
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
                          ],
                        ),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                        leading: Icon(AppIconsFill.calendarBlank, color: AppColors.verdeAguaProfundo),
                        title: const Text('Repetir até'),
                        subtitle: Text(
                          _recurrenceUntil == null
                              ? 'Sem data final (até você parar)'
                              : DateFormat("d 'de' MMMM 'de' y", 'pt_BR').format(_recurrenceUntil!),
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: TextButton(onPressed: _pickUntil, child: const Text('Definir')),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSave ? _save : null,
                  child: Text(_isEdit ? 'Salvar alterações' : 'Salvar despesa'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Percentual → texto do campo (pt-BR, vírgula decimal), até 4 casas e sem
/// zeros à toa: 33.3333 → "33,3333", 50.0 → "50". As 4 casas mantêm a soma
/// perto de 100 dentro da tolerância de validação ao reabrir para editar.
String _pctText(double v) {
  var s = v.toStringAsFixed(4);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return s.replaceAll('.', ',');
}

/// Aviso no topo da folha ao editar uma recorrência afetada por uma saída:
/// já removemos quem saiu e reequilibramos — basta o dono conferir e salvar.
class _ReviewNotice extends StatelessWidget {
  final RecurrenceReview review;
  const _ReviewNotice({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payer = review == RecurrenceReview.payerLeft;
    final color = payer ? AppColors.coralAceso : const Color(0xFFB78A2E);
    final text = payer
        ? 'Quem pagava esta recorrência saiu do grupo. Escolha quem passa a pagar '
            'e confira o rateio antes de salvar.'
        : 'Um participante saiu do grupo. Já tiramos essa pessoa e reequilibramos '
            'o rateio entre quem ficou — a próxima cobrança já sai assim. Salve só '
            'se quiser fixar essa mudança ou ajustar algo.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.repeat, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _SplitTypeSelector extends StatelessWidget {
  final SplitType selected;
  final ValueChanged<SplitType> onChanged;
  const _SplitTypeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Row(
        children: [
          for (final t in SplitType.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selected == t ? AppColors.verdeAguaProfundo : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    t.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected == t ? Colors.white : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  final String name;
  final String avatarName;
  final String? avatarLastName;
  final bool selected;
  final SplitType type;
  final TextEditingController inputController;
  final String? shareLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onInputChanged;

  const _ParticipantRow({
    required this.name,
    required this.avatarName,
    this.avatarLastName,
    required this.selected,
    required this.type,
    required this.inputController,
    required this.shareLabel,
    required this.onToggle,
    required this.onInputChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showInput = selected && type != SplitType.equal;
    // Sufixo curto para não comer o espaço do número (#4).
    final suffix = switch (type) {
      SplitType.percentage => '%',
      SplitType.weight => 'x',
      _ => null,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            activeColor: AppColors.verdeAguaProfundo,
            onChanged: (v) => onToggle(v ?? false),
          ),
          MemberAvatar(name: avatarName, lastName: avatarLastName, size: 34),
          const SizedBox(width: 10),
          // Nome + valor calculado como subtítulo (deixa o campo respirar).
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                if (selected && shareLabel != null)
                  Text(
                    type == SplitType.weight ? '= $shareLabel' : shareLabel!,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.verdeAguaProfundo),
                  ),
              ],
            ),
          ),
          if (showInput)
            SizedBox(
              width: 132,
              child: TextField(
                controller: inputController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                onChanged: (_) => onInputChanged(),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  prefixText: type == SplitType.exact ? r'R$ ' : null,
                  suffixText: suffix,
                  hintText: type == SplitType.weight ? 'partes' : null,
                ),
              ),
            )
          else if (selected)
            Text(shareLabel ?? '', style: AppTheme.moneyStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
