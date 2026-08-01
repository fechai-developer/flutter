import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/categories.dart';
import '../../core/icons.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/category_picker.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/sheet_handle.dart';
import '../../data/models/expense.dart';
import '../../data/models/expense_group.dart';
import '../../data/repositories/providers.dart';
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
    // No computador o sheet do M3 trava em 640px e fica "fino": alargamos ~25%
    // (800) para os tipos de despesa não quebrarem em tantas linhas. No celular
    // (tela < 800) isto não restringe nada — segue ocupando a largura toda.
    constraints: const BoxConstraints(maxWidth: 800),
    builder: (_) => ExpenseSheet(group: group, existing: existing),
  );
}

class ExpenseSheet extends ConsumerStatefulWidget {
  final ExpenseGroup group;
  final Expense? existing;
  const ExpenseSheet({super.key, required this.group, this.existing});

  @override
  ConsumerState<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<ExpenseSheet> {
  late final TextEditingController _descController;
  late final TextEditingController _amountController;
  late String _paidBy;
  late SplitType _type;
  String? _category;
  late DateTime _date;
  late Set<String> _participants;
  bool _recurring = false;
  DateTime? _recurrenceUntil;
  late int _recurrenceDay;

  /// Inputs por pessoa para %, partes e valor exato.
  final Map<String, TextEditingController> _inputs = {};

  /// Último rateio digitado em cada tipo, para o usuário poder passear entre as
  /// abas sem perder o que montou. Ver [_onTypeChanged].
  final Map<SplitType, Map<String, String>> _typeDrafts = {};

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
    _category = e?.category;
    // Data do lançamento: ao editar mantém a salva; ao criar, vem HOJE por padrão
    // (o usuário pode alterar).
    _date = e?.date ?? DateTime.now();
    _recurring = e?.isRecurring ?? false;
    _recurrenceUntil = e?.recurrenceUntil;
    // Dia da recorrência: usa o salvo; senão o dia do lançamento (limitado a 27).
    _recurrenceDay = e?.recurrenceDay ?? _date.day.clamp(1, 27);
    // Ao editar, tira do rateio quem foi removido → rebalanceia entre os ativos.
    _participants = e != null
        ? e.shares.keys.where((id) => !widget.group.isRemoved(id)).toSet()
        : active.map((m) => m.id).toSet();

    // Cria os controllers vazios e, ao EDITAR, repreenche cada campo.
    // Preferência absoluta pelo que a pessoa DIGITOU (`splitInputs`): o dinheiro
    // não volta a virar partes de forma confiável — 3:2:1 de R$ 100 vira
    // 50,00/33,33/16,67 e a razão se perde no arredondamento. Só caímos na
    // derivação a partir das cotas em despesas antigas, sem esse dado.
    for (final m in active) {
      _inputs[m.id] = TextEditingController();
    }
    if (e != null) {
      final seed = _seedFor(e.type);
      seed.forEach((id, txt) => _inputs[id]?.text = txt);
      // O tipo original vira rascunho: se a pessoa passear por outras abas e
      // voltar, encontra o que tinha — não uma reconstrução aproximada.
      _typeDrafts[e.type] = seed;
    }
  }

  /// Campos iniciais para [type] ao ABRIR a folha de edição.
  Map<String, String> _seedFor(SplitType type) {
    final e = widget.existing!;
    final ids = _participants.toList();
    final typed = e.splitInputs;
    if (type == e.type && typed != null) {
      return {for (final id in ids) id: _inputText(type, typed[id] ?? 0)};
    }
    return _inputsForType(type, e.shares, ids, e.amount);
  }

  /// Número → texto do campo, no formato de cada tipo.
  static String _inputText(SplitType type, double v) => switch (type) {
        SplitType.equal => '',
        SplitType.exact => Money.plain(v),
        SplitType.percentage => _pctText(v),
        // Partes são inteiras na prática ("3x"); só mostra decimal se houver.
        SplitType.weight => v == v.roundToDouble() ? '${v.round()}' : _pctText(v),
      };

  /// Texto de cada campo por pessoa que representa [shares] sob um dado [type].
  /// Usado na conversão entre abas e nas despesas antigas (sem `splitInputs`).
  static Map<String, String> _inputsForType(
      SplitType type, Map<String, double> shares, List<String> ids, double amount) {
    switch (type) {
      case SplitType.equal:
        return {for (final id in ids) id: ''};
      case SplitType.exact:
        return {for (final id in ids) id: Money.plain(shares[id] ?? 0)};
      case SplitType.percentage:
        return {for (final id in ids) id: _pctText(amount > 0 ? (shares[id] ?? 0) / amount * 100 : 0)};
      case SplitType.weight:
        return _weightTexts(shares, ids);
    }
  }

  /// Partes a partir das cotas em dinheiro — melhor esforço.
  ///
  /// O GCD dos centavos só funciona quando a divisão foi exata: 3:2:1 de R$ 300
  /// dá 18000/12000/6000 (mdc 6000 → 3,2,1), mas de R$ 100 dá 5000/3333/1667,
  /// cujo mdc é 1 — e o campo mostrava "5000, 3333, 1667". Aqui normalizamos
  /// pela MENOR cota e procuramos o menor multiplicador que deixe todos perto de
  /// inteiros, que é o que devolve 3, 2, 1 nos dois casos.
  static Map<String, String> _weightTexts(Map<String, double> shares, List<String> ids) {
    final vals = {for (final id in ids) id: shares[id] ?? 0};
    final positivos = vals.values.where((v) => v > 0.005).toList();
    if (positivos.isEmpty) return {for (final id in ids) id: ''};
    final menor = positivos.reduce(math.min);

    for (var k = 1; k <= 24; k++) {
      final escalado = {for (final e in vals.entries) e.key: e.value / menor * k};
      final cabe = escalado.values.every((v) =>
          v <= 999 && (v - v.roundToDouble()).abs() <= 0.02 * k);
      if (cabe) {
        return {for (final e in escalado.entries) e.key: '${e.value.round()}'};
      }
    }
    // Proporção que não vira partes pequenas (ex.: 1 : 7,3). Mostra o valor —
    // é feio, mas é honesto: o usuário vê o que está lá e ajusta.
    return {for (final e in vals.entries) e.key: Money.plain(e.value)};
  }

  /// Troca o tipo de divisão.
  ///
  /// Se a pessoa já mexeu neste tipo antes (inclusive o tipo com que a despesa
  /// foi salva), volta o rascunho dela. Senão, converte proporcionalmente a
  /// partir das cotas atuais. Sem isso, passar por "Igual" apagava o rateio: a
  /// volta era calculada de cotas idênticas e todo mundo virava "1x".
  void _onTypeChanged(SplitType t) {
    if (t == _type) return;
    final atual = _previewShares; // shares sob o tipo atual + inputs
    setState(() {
      if (_type != SplitType.equal) {
        _typeDrafts[_type] = {for (final id in _inputs.keys) id: _inputs[id]!.text};
      }
      _type = t;
      final draft = _typeDrafts[t];
      final seed = draft ?? _inputsForType(t, atual, _participants.toList(), _amount);
      for (final id in _inputs.keys) {
        _inputs[id]!.text = seed[id] ?? '';
      }
    });
  }

  /// Volta a despesa ao tipo e ao rateio com que ela estava salva.
  void _restoreSavedSplit() {
    final e = widget.existing!;
    setState(() {
      _type = e.type;
      _participants = e.shares.keys.where((id) => !widget.group.isRemoved(id)).toSet();
      final seed = _seedFor(e.type);
      for (final id in _inputs.keys) {
        _inputs[id]!.text = seed[id] ?? '';
      }
    });
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

  /// Editando, a divisão saiu do tipo com que a despesa foi salva. É o caso do
  /// toque sem querer em "Igual": o rateio na tela deixa de ser o que está
  /// valendo, e a pessoa precisa saber disso ANTES de salvar.
  bool get _splitTypeChanged => _isEdit && _type != widget.existing!.type;

  Future<void> _confirmAndSave() async {
    if (_splitTypeChanged) {
      final antes = widget.existing!.type.label;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mudar a divisão?'),
          content: Text(
            'Esta despesa estava dividida por "$antes" e vai passar a ser '
            'por "${_type.label}". O quanto cada um deve muda.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar assim')),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
    }
    _save();
  }

  void _save() {
    final expense = Expense.create(
      id: widget.existing?.id ??
          'e_${DateTime.now().microsecondsSinceEpoch}_${_descController.text.hashCode}',
      description: _descController.text.trim(),
      amount: _amount,
      paidByPersonId: _paidBy,
      type: _type,
      participantIds: _participants.toList(),
      inputs: _rawInputs,
      date: _date,
      recurrence: _recurring ? Recurrence.monthly : Recurrence.none,
      recurrenceUntil: _recurring ? _recurrenceUntil : null,
      recurrenceDay: _recurring ? _recurrenceDay : null,
      // Preserva o vínculo de ocorrência gerada (senão editar orfanaria a linha
      // e a geração recriaria aquele mês, duplicando).
      recurrenceParentId: widget.existing?.recurrenceParentId,
      occurrencePeriod: widget.existing?.occurrencePeriod,
      category: _category,
    );
    Navigator.of(context).pop(ExpenseSheetResult.save(expense));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      helpText: 'Data da despesa',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickUntil() async {
    final now = DateTime.now();
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
    final usedCategories = ref.watch(usedExpenseCategoriesProvider);

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
              const SizedBox(height: 12),
              // Data da despesa — vem hoje por padrão, editável (#1).
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Data'),
                  child: Row(
                    children: [
                      Icon(AppIconsFill.calendarBlank, size: 18, color: AppColors.verdeAguaProfundo),
                      const SizedBox(width: 8),
                      Text(DateFormat("d 'de' MMM 'de' y", 'pt_BR').format(_date)),
                      const Spacer(),
                      Text('Alterar', style: TextStyle(color: AppColors.verdeAguaProfundo, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Tipo', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              CategoryPicker(
                categories: kExpenseCategories,
                value: _category,
                history: usedCategories,
                onChanged: (v) => setState(() => _category = v),
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
                onChanged: _onTypeChanged,
              ),
              // Toque sem querer em "Igual" perdia o rateio montado, sem deixar
              // claro se aquilo já estava valendo. Agora o estado é explícito e
              // tem volta em um toque.
              if (_splitTypeChanged) ...[
                const SizedBox(height: 8),
                _SplitChangedNotice(
                  from: widget.existing!.type,
                  to: _type,
                  onUndo: _restoreSavedSplit,
                ),
              ],
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
                  onPressed: _canSave ? _confirmAndSave : null,
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

/// Aviso de que a divisão saiu do tipo salvo, com volta em um toque.
///
/// Sem isto, tocar em "Igual" numa despesa dividida por partes apagava o rateio
/// silenciosamente: a pessoa não sabia se aquilo já tinha sido salvo, se bastava
/// fechar, ou se teria de digitar tudo de novo.
class _SplitChangedNotice extends StatelessWidget {
  final SplitType from;
  final SplitType to;
  final VoidCallback onUndo;
  const _SplitChangedNotice({required this.from, required this.to, required this.onUndo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const color = Color(0xFFB78A2E);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(AppIcons.warningCircle, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Salva por "${from.label}", agora está por "${to.label}". '
              'Nada muda até você salvar.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: AppColors.verdeAguaProfundo,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            onPressed: onUndo,
            child: const Text('Desfazer'),
          ),
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
