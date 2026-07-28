import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils/currency.dart';
import '../../data/models/caixinha.dart';

/// Gera e compartilha/imprime o relatório financeiro da caixinha em PDF:
/// extrato (patrimônio, membros, valores emprestados) + uma projeção estimada
/// (opcional). Sem emojis no PDF (as fontes base não os renderizam).
Future<void> shareCaixinhaReport(Caixinha c, {ProjectionResult? projection, bool includeHistory = false}) async {
  const teal = PdfColor.fromInt(0xFF0E6E64);
  const soft = PdfColor.fromInt(0xFF5B726C);
  const line = PdfColor.fromInt(0xFFEAF1EE);

  String m(double v) => Money.format(v);
  String pct(double v) => '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)}%';

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

  final members = c.contributingMembers;
  final doc = pw.Document();

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (ctx) => [
      // Cabeçalho
      pw.Text(c.name, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.Text('Relatório da caixinha${c.isClosed ? ' (encerrada)' : ''}', style: const pw.TextStyle(fontSize: 10, color: soft)),
      pw.Divider(color: line),

      // Resumo
      h('Resumo'),
      kv('Patrimônio total', m(c.patrimony), strong: true),
      kv('Em caixa', m(c.cashOnHand)),
      kv('Emprestado (a receber)', m(c.outstandingReceivables)),
      kv('Total rendido', m(c.totalEarnings)),
      kv('Juros padrão dos empréstimos', pct(c.defaultInterestPct)),
      kv('Participantes', '${c.memberCount}'),

      // Membros / partilha
      h('Partilha por participante'),
      pw.Table(
        border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: line)),
        columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(2)},
        children: [
          trow(['Participante', 'Aportou', 'Participação', 'Parte'], header: true),
          for (final mm in members)
            trow([
              mm.person.id == 'me' ? 'Você' : mm.person.fullName,
              m(c.contributedBy(mm.person.id)),
              pct(c.participationOf(mm.person.id) * 100),
              m(c.balanceOf(mm.person.id)),
            ]),
        ],
      ),

      // Valores emprestados
      if (c.loans.isNotEmpty) ...[
        h('Valores emprestados'),
        pw.Table(
          border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: line)),
          columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(2)},
          children: [
            trow(['Pessoa', 'Pegou', 'Pagou', 'Deve'], header: true),
            for (final l in c.loans)
              trow([
                '${l.borrowerName} ${c.loanIsInternal(l) ? '(membro)' : '(de fora)'}',
                m(l.principal),
                m(c.repaidOf(l.id)),
                m(c.outstandingOf(l)),
              ]),
          ],
        ),
      ],

      // Projeção (estimativa)
      if (projection != null) ...[
        h('Projeção — estimativa (${projection.months} meses a ${pct(projection.monthlyRatePct)}/mês)'),
        pw.Table(
          border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: line)),
          columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(2)},
          children: [
            trow(['Participante', 'Vai colocar', 'Rendimento', 'Projetado'], header: true),
            for (final pp in projection.people)
              trow([
                pp.personId == 'me' ? 'Você' : pp.name,
                m(pp.contributed),
                m(pp.profit),
                m(pp.projected),
              ]),
            trow(['Total', m(projection.totalContributed), m(projection.totalYield), m(projection.totalProjected)], header: true),
          ],
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'Estimativa assumindo que todos aportam a cota em dia todos os meses e um rendimento '
            'médio constante. NÃO considera os valores emprestados (entre participantes ou externos). '
            'É apenas uma simulação, não uma garantia.',
            style: const pw.TextStyle(fontSize: 8, color: soft, fontStyle: pw.FontStyle.italic),
          ),
        ),
      ],

      // Histórico de movimentações (opcional)
      if (includeHistory && c.movements.isNotEmpty) ...[
        h('Histórico'),
        pw.Table(
          border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: line)),
          columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(4), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(2)},
          children: [
            trow(['Data', 'Movimentação', 'Valor', 'Saldo'], header: true),
            for (final mv in c.movements)
              trow([
                _fmtDate(mv.date),
                mv.label,
                '${mv.amount >= 0 ? '+' : '-'} ${m(mv.amount.abs())}',
                m(mv.balanceAfter),
              ]),
          ],
        ),
      ],

      // Rodapé / enquadramento
      pw.SizedBox(height: 24),
      pw.Divider(color: line),
      pw.Text(
        'O Fechaí organiza finanças pessoais entre pessoas de confiança. Não é instituição '
        'financeira: não empresta, não cobra e não guarda dinheiro. Valores e taxas são combinados '
        'entre os participantes. Documento gerado pelo próprio grupo para conferência.',
        style: const pw.TextStyle(fontSize: 8, color: soft),
      ),
    ],
  ));

  await Printing.sharePdf(bytes: await doc.save(), filename: 'caixinha-${_slug(c.name)}.pdf');
}

String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
