import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils/balance.dart';
import '../../core/utils/currency.dart';
import '../../data/models/expense_group.dart';
import '../stats/category_breakdown.dart';

/// Gera e compartilha/imprime o relatório da conta em PDF: resumo,
/// indicadores, saldos por participante, despesas por tipo e histórico.
/// Espelha o relatório da Caixinha (`caixinha_report.dart`).
Future<void> shareGroupReport(ExpenseGroup g) async {
  const teal = PdfColor.fromInt(0xFF0E6E64);
  const soft = PdfColor.fromInt(0xFF5B726C);
  const line = PdfColor.fromInt(0xFFEAF1EE);

  String m(double v) => Money.format(v);

  pw.Widget h(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: teal)),
      );

  pw.Widget kv(String k, String v, {bool strong = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(k, style: const pw.TextStyle(fontSize: 10, color: soft)),
            pw.Text(v, style: pw.TextStyle(fontSize: 10, fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  pw.TableRow trow(List<String> cells, {bool header = false}) => pw.TableRow(
        decoration: header ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5FBF9)) : null,
        children: [
          for (var i = 0; i < cells.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: pw.Text(
                cells[i],
                textAlign: i == 0 ? pw.TextAlign.left : pw.TextAlign.right,
                style: pw.TextStyle(fontSize: 9, fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal),
              ),
            ),
        ],
      );

  final members = g.activeMembers;
  final balances = BalanceCalculator.netBalances(g);
  final settlements = BalanceCalculator.simplify(g);
  final slices = aggregateByCategory(g.expenses.map((e) => (category: e.category, amount: e.amount)));
  final minhaParte = g.expenses.fold(0.0, (a, e) => a + (e.shares['me'] ?? 0));

  final doc = pw.Document();

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (ctx) => [
      // Cabeçalho
      pw.Text(g.name, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.Text('Relatório da conta', style: const pw.TextStyle(fontSize: 10, color: soft)),
      pw.Divider(color: line),

      // Resumo
      h('Resumo'),
      kv('Total da conta', m(g.total), strong: true),
      kv('Sua parte', m(minhaParte)),
      kv('Nº de despesas', '${g.expenses.length}'),
      kv('Participantes', '${members.length}'),

      // Saldos
      h('Saldos por participante'),
      pw.Table(
        border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: line)),
        columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)},
        children: [
          trow(['Participante', 'Saldo'], header: true),
          for (final mm in members)
            trow([
              mm.id == 'me' ? 'Você' : mm.fullName,
              m(balances[mm.id] ?? 0),
            ]),
        ],
      ),
      if (settlements.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Text('Acertos sugeridos', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        for (final s in settlements)
          kv(
            '${s.fromPersonId == 'me' ? 'Você' : g.memberById(s.fromPersonId)?.fullName ?? '?'} → '
            '${s.toPersonId == 'me' ? 'Você' : g.memberById(s.toPersonId)?.fullName ?? '?'}',
            m(s.amount),
          ),
      ],

      // Despesas por tipo
      if (slices.isNotEmpty) ...[
        h('Despesas por tipo'),
        pw.Table(
          border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: line)),
          columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(2)},
          children: [
            trow(['Tipo', 'Nº', 'Total'], header: true),
            for (final s in slices) trow([s.label, '${s.count}', m(s.value)]),
          ],
        ),
      ],

      // Despesas (extrato)
      if (g.expenses.isNotEmpty) ...[
        h('Despesas'),
        pw.Table(
          border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: line)),
          columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(4), 2: pw.FlexColumnWidth(3), 3: pw.FlexColumnWidth(2)},
          children: [
            trow(['Data', 'Descrição', 'Pago por', 'Valor'], header: true),
            for (final e in [...g.expenses]..sort((a, b) => b.date.compareTo(a.date)))
              trow([
                _fmtDate(e.date),
                e.description,
                e.paidByPersonId == 'me' ? 'Você' : g.memberById(e.paidByPersonId)?.name ?? '?',
                m(e.amount),
              ]),
          ],
        ),
      ],

      // Histórico (despesas + acertos, extrato cronológico)
      if (g.payments.isNotEmpty) ...[
        h('Acertos registrados'),
        pw.Table(
          border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: line)),
          columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(4), 2: pw.FlexColumnWidth(2)},
          children: [
            trow(['Data', 'De → Para', 'Valor'], header: true),
            for (final p in [...g.payments]..sort((a, b) => b.date.compareTo(a.date)))
              trow([
                _fmtDate(p.date),
                '${p.fromId == 'me' ? 'Você' : g.memberById(p.fromId)?.name ?? '?'} → '
                    '${p.toId == 'me' ? 'Você' : g.memberById(p.toId)?.name ?? '?'}',
                m(p.amount),
              ]),
          ],
        ),
      ],

      // Rodapé
      pw.SizedBox(height: 24),
      pw.Divider(color: line),
      pw.Text(
        'O Fechaí organiza finanças pessoais entre pessoas de confiança. Não é instituição '
        'financeira: não empresta, não cobra e não guarda dinheiro. Documento gerado pela própria '
        'conta para conferência.',
        style: const pw.TextStyle(fontSize: 8, color: soft),
      ),
    ],
  ));

  await Printing.sharePdf(bytes: await doc.save(), filename: 'conta-${_slug(g.name)}.pdf');
}

String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
