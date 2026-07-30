import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fechai/data/models/expense.dart';
import 'package:fechai/data/models/expense_group.dart';
import 'package:fechai/data/models/person.dart';
import 'package:fechai/data/repositories/providers.dart';
import 'package:fechai/features/groups/expense_sheet.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  // Grupo mínimo com você + 2 pessoas.
  final group = ExpenseGroup(
    id: 'g',
    name: 'Teste',
    emoji: '🏠',
    createdAt: DateTime(2026, 7, 20),
    members: const [
      Person(id: 'me', name: 'Você'),
      Person(id: 'p_ana', name: 'Ana', lastName: 'Prado'),
      Person(id: 'p_bru', name: 'Bruno', lastName: 'Lima'),
    ],
    expenses: const [],
  );

  Future<void> pumpSheet(WidgetTester tester, Expense existing) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [usedExpenseCategoriesProvider.overrideWithValue(const [])],
      child: MaterialApp(
        home: Scaffold(body: ExpenseSheet(group: group, existing: existing)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  ElevatedButton saveButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.byType(ElevatedButton));

  testWidgets('editar despesa por porcentagem mantém Salvar habilitado', (tester) async {
    final e = Expense.create(
      id: 'e1',
      description: 'Jantar',
      amount: 100,
      paidByPersonId: 'me',
      type: SplitType.percentage,
      participantIds: const ['me', 'p_ana', 'p_bru'],
      inputs: const {'me': 40, 'p_ana': 30, 'p_bru': 30},
      date: DateTime(2026, 7, 20),
    );
    await pumpSheet(tester, e);
    expect(saveButton(tester).onPressed, isNotNull,
        reason: 'os campos de % devem ser repreenchidos ao editar');
  });

  testWidgets('editar despesa por partes mantém Salvar habilitado', (tester) async {
    final e = Expense.create(
      id: 'e2',
      description: 'Uber',
      amount: 90,
      paidByPersonId: 'me',
      type: SplitType.weight,
      participantIds: const ['me', 'p_ana', 'p_bru'],
      inputs: const {'me': 1, 'p_ana': 1, 'p_bru': 1},
      date: DateTime(2026, 7, 20),
    );
    await pumpSheet(tester, e);
    expect(saveButton(tester).onPressed, isNotNull,
        reason: 'os campos de partes devem ser repreenchidos ao editar');
  });

  testWidgets('editar despesa por valor exato mantém Salvar habilitado', (tester) async {
    final e = Expense.create(
      id: 'e3',
      description: 'Mercado',
      amount: 50,
      paidByPersonId: 'me',
      type: SplitType.exact,
      participantIds: const ['me', 'p_ana'],
      inputs: const {'me': 20, 'p_ana': 30},
      date: DateTime(2026, 7, 20),
    );
    await pumpSheet(tester, e);
    expect(saveButton(tester).onPressed, isNotNull);
  });

  // Valores dos campos de participante, filtrados pelo sufixo do tipo atual.
  List<String> inputsWithSuffix(WidgetTester tester, String suffix) =>
      (tester.widgetList<TextField>(find.byType(TextField))
              .where((f) => f.decoration?.suffixText == suffix)
              .map((f) => f.controller?.text ?? '')
              .toList())
        ..sort();

  testWidgets('editar por partes abre como razão reduzida (2,2,1), não R\$ (120,120,60)', (tester) async {
    // 300 dividido 2:2:1 → shares 120,120,60. Ao reabrir deve mostrar 2,2,1.
    final e = Expense.create(
      id: 'e_w',
      description: 'Rateio',
      amount: 300,
      paidByPersonId: 'me',
      type: SplitType.weight,
      participantIds: const ['me', 'p_ana', 'p_bru'],
      inputs: const {'me': 2, 'p_ana': 2, 'p_bru': 1},
      date: DateTime(2026, 7, 20),
    );
    await pumpSheet(tester, e);
    expect(inputsWithSuffix(tester, 'x'), ['1', '2', '2']);
    expect(find.text('120'), findsNothing);
  });

  testWidgets('trocar de Partes para Porcentagem converte proporcional (40/40/20)', (tester) async {
    final e = Expense.create(
      id: 'e_w2',
      description: 'Rateio',
      amount: 300,
      paidByPersonId: 'me',
      type: SplitType.weight,
      participantIds: const ['me', 'p_ana', 'p_bru'],
      inputs: const {'me': 2, 'p_ana': 2, 'p_bru': 1},
      date: DateTime(2026, 7, 20),
    );
    await pumpSheet(tester, e);
    await tester.ensureVisible(find.text('Porcentagem'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Porcentagem'));
    await tester.pumpAndSettle();
    // 120/300 = 40%, 60/300 = 20%.
    expect(inputsWithSuffix(tester, '%'), ['20', '40', '40']);
    expect(saveButton(tester).onPressed, isNotNull);
  });
}
