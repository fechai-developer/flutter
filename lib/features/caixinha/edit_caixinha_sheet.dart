import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/limits.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/emoji_picker.dart';
import '../../core/widgets/sheet_handle.dart';
import '../../data/models/caixinha.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';

/// Editar caixinha: nome, ícone, valor da cota e juros padrão dos empréstimos.
/// Só o dono. Não mexe em aportes/rendimentos/empréstimos já lançados.
Future<void> showEditCaixinhaSheet(BuildContext context, Caixinha c) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EditCaixinhaSheet(caixinha: c),
  );
}

/// Campo de data tappável (usado na edição).
class _DateTile extends StatelessWidget {
  final String label;
  final String text;
  final VoidCallback onTap;
  const _DateTile({required this.label, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.areiaNeutra),
        ),
        child: Row(
          children: [
            Icon(AppIconsFill.calendarBlank, size: 18, color: AppColors.verdeAguaProfundo),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  Text(text, style: theme.textTheme.titleMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditCaixinhaSheet extends ConsumerStatefulWidget {
  final Caixinha caixinha;
  const EditCaixinhaSheet({super.key, required this.caixinha});

  @override
  ConsumerState<EditCaixinhaSheet> createState() => _EditCaixinhaSheetState();
}

class _EditCaixinhaSheetState extends ConsumerState<EditCaixinhaSheet> {
  late final TextEditingController _name;
  late final TextEditingController _quota;
  late final TextEditingController _paymentDay;
  late String _emoji;
  late double _interest;
  late DateTime _startDate;
  DateTime? _endDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.caixinha;
    _name = TextEditingController(text: c.name);
    _quota = TextEditingController(text: c.monthlyQuota > 0 ? Money.plain(c.monthlyQuota) : '');
    _paymentDay = TextEditingController(text: c.paymentDay?.toString() ?? '');
    _emoji = c.emoji;
    _interest = c.defaultInterestPct;
    _startDate = c.periodStart;
    _endDate = c.endDate;
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );

  static String _fmt(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  void dispose() {
    _name.dispose();
    _quota.dispose();
    _paymentDay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dê um nome pra caixinha')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(repositoryControllerProvider).updateCaixinha(
            widget.caixinha.id,
            name: _name.text.trim(),
            emoji: _emoji,
            defaultInterestPct: _interest,
            monthlyQuota: Money.parse(_quota.text) ?? 0,
            startDate: _startDate,
            endDate: _endDate,
            paymentDay: int.tryParse(_paymentDay.text.trim())?.clamp(1, 31),
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
    final warn = _interest > 10;
    final accent = warn ? AppColors.coralAceso : AppColors.verdeAguaProfundo;

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
              Text('Editar caixinha', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              EmojiPicker(
                value: _emoji,
                presets: const ['🐷', '💰', '🏦', '💵', '🤝', '👨‍👩‍👧', '🏠', '🎯', '📈', '🪙'],
                onChanged: (e) => setState(() => _emoji = e),
              ),
              const SizedBox(height: 16),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome')),
              const SizedBox(height: 12),
              TextField(
                controller: _quota,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Valor da cota por participante',
                  prefixText: r'R$ ',
                  helperText: 'Vale pra frente — não altera aportes já lançados.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _paymentDay,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                decoration: const InputDecoration(
                  labelText: 'Dia do pagamento (todo mês)',
                  hintText: 'ex.: 10',
                  helperText: 'A partir desse dia, a cota não paga passa a render juros. Opcional.',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 20),
              Text('Período', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DateTile(
                      label: 'Primeira parcela',
                      text: _fmt(_startDate),
                      onTap: () async {
                        final d = await _pickDate(_startDate);
                        if (d != null) setState(() => _startDate = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateTile(
                      label: 'Até (opcional)',
                      text: _fmt(_endDate),
                      onTap: () async {
                        final d = await _pickDate(_endDate ?? _startDate);
                        if (d != null) setState(() => _endDate = d);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('Juros dos empréstimos', style: theme.textTheme.labelLarge),
                  const Spacer(),
                  Text('${_interest.toStringAsFixed(_interest.truncateToDouble() == _interest ? 0 : 1)}% ao mês',
                      style: AppTheme.moneyStyle(fontSize: 16, color: accent)),
                ],
              ),
              Slider(
                value: _interest,
                min: 0,
                max: InterestPolicy.maxPct,
                divisions: (InterestPolicy.maxPct * 2).toInt(),
                activeColor: accent,
                label: '${_interest.toStringAsFixed(1)}%',
                onChanged: (v) => setState(() => _interest = v),
              ),
              const SizedBox(height: 12),
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
