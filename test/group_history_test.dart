import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:fechai/data/models/expense.dart';
import 'package:fechai/data/models/expense_group.dart';
import 'package:fechai/data/models/person.dart';
import 'package:fechai/data/repositories/app_repository.dart';
import 'package:fechai/data/repositories/in_memory_repository.dart';
import 'package:fechai/data/repositories/providers.dart';
import 'package:fechai/features/groups/group_detail_screen.dart';

/// Repositório de teste: devolve uma conta fixa (sem delays), para montar a
/// tela de detalhe e conferir a aba Histórico e a parte do usuário na despesa.
class _FakeRepo extends InMemoryRepository {
  final ExpenseGroup fixture;
  _FakeRepo(this.fixture);

  @override
  Future<List<ExpenseGroup>> groups() async => [fixture];

  @override
  Future<ExpenseGroup> groupById(String id) async => fixture;
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  const me = Person(id: 'me', name: 'Você');
  const ana = Person(id: 'ana', name: 'Ana', lastName: 'Prado');

  final group = ExpenseGroup(
    id: 'g1',
    name: 'Viagem',
    emoji: '🏖️',
    createdAt: DateTime(2026, 1, 1),
    members: const [me, ana],
    expenses: [
      Expense.equalSplit(
        id: 'e1',
        description: 'Hotel',
        amount: 200,
        paidByPersonId: 'me',
        date: DateTime(2026, 1, 5),
        participantIds: const ['me', 'ana'],
      ),
    ],
    payments: [
      Payment(id: 'p1', fromId: 'ana', toId: 'me', amount: 100, date: DateTime(2026, 1, 6)),
    ],
  );

  Future<void> pump(WidgetTester tester, {ExpenseGroup? fixture}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRepositoryProvider.overrideWithValue(_FakeRepo(fixture ?? group) as AppRepository),
        ],
        child: const MaterialApp(home: GroupDetailScreen(groupId: 'g1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('aba Despesas mostra a parte do usuário entre parênteses', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Despesas'));
    await tester.pumpAndSettle();
    expect(find.textContaining('100,00'), findsWidgets); // parte de 'me' (metade de 200)
    expect(tester.takeException(), isNull);
  });

  // Item 4: no celular a linha da despesa vira DUAS faixas — título + valor em
  // cima, "quem pagou · quando" e "sua parte" embaixo — em vez de espremer tudo
  // em três colunas. No PC continua em coluna única à direita.
  //
  // Nota: não dá para checar overflow aqui. O ambiente de teste não baixa as
  // fontes do google_fonts e substitui por uma métrica bem mais larga, então
  // qualquer texto "estoura" independentemente do layout. O que este teste
  // trava é a ESTRUTURA: onde cada informação fica.
  final comCategoria = ExpenseGroup(
    id: group.id,
    name: group.name,
    emoji: group.emoji,
    createdAt: group.createdAt,
    members: group.members,
    payments: group.payments,
    expenses: [
      Expense.equalSplit(
        id: 'e1',
        description: 'Jantar de despedida no restaurante da esquina',
        amount: 1234.56,
        paidByPersonId: 'ana',
        date: DateTime(2026, 1, 5),
        participantIds: const ['me', 'ana'],
        category: 'Alimentação',
      ),
    ],
  );

  Future<void> abrirDespesas(WidgetTester tester, {Size? tela}) async {
    if (tela != null) {
      tester.view.physicalSize = tela;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    await pump(tester, fixture: comCategoria);
    await tester.tap(find.text('Despesas'));
    await tester.pumpAndSettle();
    // Descarta os overflows de fonte substituída (ver nota acima).
    while (tester.takeException() != null) {}
  }

  testWidgets('celular: "sua parte" desce para a segunda faixa e o tipo sai do texto', (tester) async {
    await abrirDespesas(tester, tela: const Size(375, 812));

    final descricao = tester.getTopLeft(find.text('Jantar de despedida no restaurante da esquina'));
    final suaParte = tester.getTopLeft(find.textContaining('sua parte'));
    expect(suaParte.dy, greaterThan(descricao.dy),
        reason: '"sua parte" fica na faixa de baixo, não colada no valor');

    // O tipo já é dito pelo ícone — no celular ele sai do texto de contexto.
    expect(find.textContaining('Ana pagou'), findsOneWidget);
    expect(find.textContaining('Alimentação'), findsNothing);
  });

  testWidgets('computador: mantém valor e "sua parte" na coluna da direita', (tester) async {
    await abrirDespesas(tester); // superfície padrão (800x600) = layout largo

    final descricao = tester.getTopLeft(find.text('Jantar de despedida no restaurante da esquina'));
    final suaParte = tester.getTopLeft(find.textContaining('sua parte'));
    expect(suaParte.dx, greaterThan(descricao.dx),
        reason: 'no layout largo "sua parte" fica à direita, abaixo do valor');

    // Com espaço sobrando, o tipo continua escrito por extenso.
    expect(find.textContaining('Alimentação'), findsOneWidget);
  });

  testWidgets('aba Histórico mostra despesa e acerto, sem exceções', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    expect(find.text('Hotel'), findsOneWidget);
    expect(find.text('Acerto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // O histórico é registro: identifica quem se envolveu por nome + sobrenome,
  // senão dois homônimos no grupo viram a mesma linha.
  testWidgets('aba Histórico identifica as pessoas por nome e sobrenome', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ana Prado pagou Você'), findsOneWidget);
  });

  // Item 1: só o acerto ganha "Desfazer" (a despesa se edita na aba Despesas),
  // e só para o dono da conta.
  testWidgets('dono vê Desfazer no acerto — e só nele', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Desfazer acerto'), findsOneWidget);
  });

  testWidgets('confirmação de desfazer nomeia as pessoas por completo', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Desfazer acerto'));
    await tester.pumpAndSettle();

    expect(find.text('Desfazer este acerto?'), findsOneWidget);
    expect(find.textContaining('Ana Prado → Você'), findsOneWidget);
  });

  testWidgets('quem não é dono não vê Desfazer', (tester) async {
    final naoDono = ExpenseGroup(
      id: group.id,
      name: group.name,
      emoji: group.emoji,
      createdAt: group.createdAt,
      members: group.members,
      expenses: group.expenses,
      payments: group.payments,
      ownerId: 'ana',
    );
    await pump(tester, fixture: naoDono);
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    expect(find.text('Acerto'), findsOneWidget);
    expect(find.byTooltip('Desfazer acerto'), findsNothing);
  });
}
