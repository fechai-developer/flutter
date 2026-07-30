import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/icons.dart';
import '../../../theme/app_theme.dart';

/// Normaliza uma data para o dia (00:00), pra comparar/mapear por dia.
DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendário mensal compacto — a "gaveta" que filtra as despesas por dia.
///
/// Marca com um ponto os dias que têm despesa ([markedDays]); tocar um dia
/// seleciona (e refiltra a lista); tocar no dia já selecionado limpa o filtro.
/// O mês visível é estado interno (setas ‹ ›); a seleção é controlada pelo pai
/// via [selectedDay] + [onDaySelected].
class MiniCalendar extends StatefulWidget {
  final DateTime initialMonth;
  final Set<DateTime> markedDays;
  final DateTime? selectedDay;
  final ValueChanged<DateTime?> onDaySelected;

  const MiniCalendar({
    super.key,
    required this.initialMonth,
    required this.markedDays,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  State<MiniCalendar> createState() => _MiniCalendarState();
}

class _MiniCalendarState extends State<MiniCalendar> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final s = widget.selectedDay ?? widget.initialMonth;
    _visibleMonth = DateTime(s.year, s.month);
  }

  void _shiftMonth(int delta) {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marked = {for (final d in widget.markedDays) dayKey(d)};
    final selected = widget.selectedDay == null ? null : dayKey(widget.selectedDay!);

    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    // weekday: Dart Mon=1..Sun=7. Grade começa no domingo → offset.
    final leadingBlanks = firstOfMonth.weekday % 7; // Sun→0, Mon→1, ...
    final monthLabel = DateFormat("MMMM 'de' y", 'pt_BR').format(firstOfMonth);

    const weekdayLabels = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${monthLabel[0].toUpperCase()}${monthLabel.substring(1)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final w in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(w, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1,
            ),
            itemCount: leadingBlanks + daysInMonth,
            itemBuilder: (context, i) {
              if (i < leadingBlanks) return const SizedBox.shrink();
              final day = i - leadingBlanks + 1;
              final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
              final isMarked = marked.contains(date);
              final isSelected = selected != null && selected == date;
              return _DayCell(
                day: day,
                marked: isMarked,
                selected: isSelected,
                onTap: () => widget.onDaySelected(isSelected ? null : date),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool marked;
  final bool selected;
  final VoidCallback onTap;
  const _DayCell({required this.day, required this.marked, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = selected ? Colors.white : theme.colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppColors.verdeAguaProfundo : Colors.transparent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                color: onColor,
                fontWeight: (marked || selected) ? FontWeight.w700 : FontWeight.w400,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: marked
                    ? (selected ? Colors.white : AppColors.mentaViva)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ícone de calendário reutilizado pelo botão que abre/fecha a gaveta.
const IconData kCalendarIcon = AppIconsFill.calendarBlank;
