import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fechai/data/models/expense.dart';
import 'package:fechai/data/models/expense_group.dart';
import 'package:fechai/data/models/person.dart';
import 'package:fechai/features/groups/expense_sheet.dart';

void main() {
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
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ExpenseSheet(group: group, existing: existing)),
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
}
