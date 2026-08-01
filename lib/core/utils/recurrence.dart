import '../../data/models/expense.dart';
import '../../data/models/expense_group.dart';

/// Geração das ocorrências mensais de despesas recorrentes.
///
/// Regras (decididas com o usuário):
///  - A despesa recorrente é o **molde** (conta como a 1ª ocorrência, no mês do
///    seu `date`). As ocorrências seguintes são despesas novas, ligadas por
///    [Expense.recurrenceParentId] e marcadas com [Expense.occurrencePeriod].
///  - Gera **apenas o mês corrente** quando vence (sem backfill retroativo): o
///    pg_cron roda diário, então cada mês nasce no dia certo. Se o cron ficar
///    parado, o mês pulado simplesmente não é recuperado (evita cobrança
///    retroativa de surpresa).
///  - Ao gerar, **quem saiu do grupo é excluído** e o rateio é **redistribuído
///    proporcionalmente mantendo o total** (vale p/ todos os tipos, já que as
///    cotas são guardadas em R$; "igual" é caso particular).
///  - Se **quem pagava saiu** (`payerLeft` / pagador removido) → a série é
///    **bloqueada** (não gera) até o dono reatribuir o pagador.
///  - Idempotente: não recria um mês que já tem ocorrência (dedupe por
///    molde + período).
class RecurrenceGenerator {
  RecurrenceGenerator._();

  /// Ocorrência do mês de [asOf] que ainda não existe (uma por molde vencido).
  /// Não muta o grupo — devolve as novas despesas para o repositório inserir.
  static List<Expense> due(ExpenseGroup group, DateTime asOf) {
    final out = <Expense>[];
    final period = DateTime(asOf.year, asOf.month); // 1º dia do mês corrente

    for (final t in group.expenses) {
      if (t.recurrence != Recurrence.monthly) continue; // só moldes mensais
      if (t.recurrenceParentId != null) continue; // ignora ocorrências geradas
      if (t.recurrenceReview == RecurrenceReview.payerLeft) continue; // bloqueado
      if (group.isRemoved(t.paidByPersonId)) continue; // pagador saiu → bloqueia

      // o molde já é a ocorrência do seu próprio mês — só geramos meses depois
      if (!period.isAfter(DateTime(t.date.year, t.date.month))) continue;

      final day = (t.recurrenceDay ?? t.date.day).clamp(1, 28);
      final billing = DateTime(period.year, period.month, day);
      if (asOf.isBefore(billing)) continue; // ainda não venceu neste mês
      if (t.recurrenceUntil != null && billing.isAfter(t.recurrenceUntil!)) continue;
      if (group.expenses.any((e) => _isOccurrence(e, t.id, period))) continue; // já existe

      final shares = _rescale(t, group);
      if (shares == null) continue;
      out.add(Expense(
        id: '${t.id}_${period.year}${period.month.toString().padLeft(2, '0')}',
        description: t.description,
        amount: t.amount,
        paidByPersonId: t.paidByPersonId,
        type: t.type,
        shares: shares,
        // Herda o rateio digitado no molde só quando ninguém saiu: se houve
        // redistribuição, "3x, 2x, 1x" já não descreve esta ocorrência, e é
        // melhor a edição derivar dos valores do que mentir.
        splitInputs: shares.length == t.shares.length ? t.splitInputs : null,
        date: billing,
        recurrenceParentId: t.id,
        occurrencePeriod: period,
      ));
    }
    return out;
  }

  static bool _isOccurrence(Expense e, String parentId, DateTime period) =>
      e.recurrenceParentId == parentId &&
      e.occurrencePeriod != null &&
      e.occurrencePeriod!.year == period.year &&
      e.occurrencePeriod!.month == period.month;

  /// Redistribui as cotas do molde entre quem **ficou**, proporcionalmente,
  /// mantendo o total. Devolve null se não há ninguém ativo no rateio.
  static Map<String, double>? _rescale(Expense t, ExpenseGroup group) {
    double round2(double v) => double.parse(v.toStringAsFixed(2));
    final staying = <String, double>{};
    t.shares.forEach((pid, share) {
      if (!group.isRemoved(pid)) staying[pid] = share;
    });
    if (staying.isEmpty) return null;

    final total = t.amount;
    final sum = staying.values.fold<double>(0, (a, b) => a + b);
    final result = <String, double>{};
    if (sum > 0) {
      staying.forEach((k, v) => result[k] = round2(v * total / sum));
    } else {
      // molde com cotas zeradas → divide igual entre os que ficaram
      final base = round2(total / staying.length);
      for (final k in staying.keys) {
        result[k] = base;
      }
    }
    // joga a sobra de arredondamento na primeira cota (fecha com o total)
    final diff = round2(total - result.values.fold<double>(0, (a, b) => a + b));
    if (diff != 0) {
      final first = result.keys.first;
      result[first] = round2(result[first]! + diff);
    }
    return result;
  }
}
