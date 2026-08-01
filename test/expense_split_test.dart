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
import 'package:fechai/features/groups/expense_sheet.dart';

/// Repositório de teste: responde na hora (o mock real usa delays, que deixam
/// timers pendentes ao fim do teste) com um grupo fixo.
class _FakeRepo extends InMemoryRepository {
  final ExpenseGroup fixture;
  _FakeRepo(this.fixture);

  @override
  Future<List<ExpenseGroup>> groups() async => [fixture];

  @override
  Future<ExpenseGroup> groupById(String id) async => fixture;
}

/// Rateio desigual: o que a pessoa digita tem que voltar igual na edição, e
/// passear pelas abas de tipo não pode apagar o que ela montou.
void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  const me = Person(id: 'me', name: 'Você');
  const ana = Person(id: 'ana', name: 'Ana', lastName: 'Prado');
  const bruno = Person(id: 'bruno', name: 'Bruno', lastName: 'Reis');
  const membros = [me, ana, bruno];

  ExpenseGroup grupoCom(List<Expense> despesas) => ExpenseGroup(
        id: 'g1',
        name: 'Viagem',
        emoji: '🏖️',
        createdAt: DateTime(2026, 1, 1),
        members: membros,
        expenses: despesas,
      );

  Expense porPartes({required double valor, required Map<String, double> partes}) =>
      Expense.create(
        id: 'e1',
        description: 'Hotel',
        amount: valor,
        paidByPersonId: 'me',
        type: SplitType.weight,
        participantIds: partes.keys.toList(),
        inputs: partes,
        date: DateTime(2026, 1, 5),
      );

  group('Expense.create guarda o rateio digitado', () {
    test('partes ficam salvas como digitadas, não como dinheiro', () {
      final e = porPartes(valor: 360, partes: {'me': 3, 'ana': 2, 'bruno': 1});
      expect(e.shares, {'me': 180.0, 'ana': 120.0, 'bruno': 60.0});
      expect(e.splitInputs, {'me': 3.0, 'ana': 2.0, 'bruno': 1.0});
    });

    test('divisão igual não guarda entrada (não há o que digitar)', () {
      final e = Expense.create(
        id: 'e2',
        description: 'Uber',
        amount: 90,
        paidByPersonId: 'me',
        type: SplitType.equal,
        participantIds: const ['me', 'ana', 'bruno'],
        date: DateTime(2026, 1, 5),
      );
      expect(e.splitInputs, isNull);
    });

    test('porcentagem quebrada sobrevive ao arredondamento do dinheiro', () {
      final e = Expense.create(
        id: 'e3',
        description: 'Conta',
        amount: 100,
        paidByPersonId: 'me',
        type: SplitType.percentage,
        participantIds: const ['me', 'ana', 'bruno'],
        inputs: const {'me': 33.33, 'ana': 33.33, 'bruno': 33.34},
        date: DateTime(2026, 1, 5),
      );
      expect(e.splitInputs, {'me': 33.33, 'ana': 33.33, 'bruno': 33.34});
    });
  });

  group('Folha de despesa — reabrir para editar', () {
    /// Textos dos campos de rateio, na ordem dos participantes. Os dois
    /// primeiros TextField da folha são descrição e valor.
    List<String> camposDeRateio(WidgetTester tester) => tester
        .widgetList<TextField>(find.byType(TextField))
        .skip(2)
        .map((f) => f.controller?.text ?? '')
        .toList();

    /// O que a folha devolveu ao fechar (o resultado do "Salvar alterações").
    late ExpenseSheetResult? resultado;

    Future<void> abrirEm(WidgetTester tester, ExpenseGroup grupo, Expense existente) async {
      // Superfície alta: a folha é comprida (descrição, valor, data, tipo,
      // quem pagou, rateio, recorrência) e o seletor de divisão fica fora dos
      // 600px padrão do teste — os toques não o alcançariam.
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      resultado = null;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRepositoryProvider.overrideWithValue(_FakeRepo(grupo) as AppRepository),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    // Passa pelo mesmo caminho do app (bottom sheet) para o
                    // teste ver o que a folha devolve ao fechar.
                    onPressed: () async {
                      resultado = await showExpenseSheet(ctx, group: grupo, existing: existente);
                    },
                    child: const Text('abrir folha'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir folha'));
      await tester.pumpAndSettle();
    }

    Future<void> abrir(WidgetTester tester, Expense existente) =>
        abrirEm(tester, grupoCom([existente]), existente);

    Expense ultimoSalvo(WidgetTester tester) {
      final r = resultado;
      expect(r, isNotNull, reason: 'a folha precisa ter fechado salvando');
      expect(r!.expense, isNotNull);
      return r.expense!;
    }

    testWidgets('divisão exata (360 em 3:2:1) volta como 3, 2, 1', (tester) async {
      await abrir(tester, porPartes(valor: 360, partes: {'me': 3, 'ana': 2, 'bruno': 1}));
      expect(camposDeRateio(tester), ['3', '2', '1']);
    });

    testWidgets('divisão inexata (100 em 3:2:1) volta como 3, 2, 1 — não 5000, 3333, 1667',
        (tester) async {
      await abrir(tester, porPartes(valor: 100, partes: {'me': 3, 'ana': 2, 'bruno': 1}));
      expect(camposDeRateio(tester), ['3', '2', '1']);
    });

    testWidgets('despesa antiga (sem o digitado) deriva das cotas em partes pequenas',
        (tester) async {
      // Espelha uma linha salva antes da coluna split_input existir.
      final legada = Expense(
        id: 'e9',
        description: 'Hotel',
        amount: 100,
        paidByPersonId: 'me',
        type: SplitType.weight,
        shares: const {'me': 50.0, 'ana': 33.33, 'bruno': 16.67},
        date: DateTime(2026, 1, 5),
      );
      await abrir(tester, legada);
      expect(camposDeRateio(tester), ['3', '2', '1']);
    });

    testWidgets('porcentagem volta como foi digitada', (tester) async {
      final e = Expense.create(
        id: 'e4',
        description: 'Conta',
        amount: 100,
        paidByPersonId: 'me',
        type: SplitType.percentage,
        participantIds: const ['me', 'ana', 'bruno'],
        inputs: const {'me': 50, 'ana': 30, 'bruno': 20},
        date: DateTime(2026, 1, 5),
      );
      await abrir(tester, e);
      expect(camposDeRateio(tester), ['50', '30', '20']);
    });

    testWidgets('passar por "Igual" e voltar NÃO apaga o rateio', (tester) async {
      await abrir(tester, porPartes(valor: 360, partes: {'me': 3, 'ana': 2, 'bruno': 1}));
      expect(camposDeRateio(tester), ['3', '2', '1']);

      await tester.tap(find.text(SplitType.equal.label));
      await tester.pumpAndSettle();
      // Em "Igual" não há campos por pessoa.
      expect(camposDeRateio(tester), isEmpty);

      await tester.tap(find.text(SplitType.weight.label));
      await tester.pumpAndSettle();
      expect(camposDeRateio(tester), ['3', '2', '1'],
          reason: 'o rateio montado volta, não vira 1x para todo mundo');
    });

    testWidgets('mudar de tipo avisa e o "Desfazer" volta ao estado salvo', (tester) async {
      await abrir(tester, porPartes(valor: 360, partes: {'me': 3, 'ana': 2, 'bruno': 1}));
      expect(find.text('Desfazer'), findsNothing);

      await tester.tap(find.text(SplitType.equal.label));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nada muda até você salvar'), findsOneWidget);

      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nada muda até você salvar'), findsNothing);
      expect(camposDeRateio(tester), ['3', '2', '1']);
    });

    // Mexer nas pessoas do rateio é o caso em que o "digitado" e as cotas
    // poderiam sair de sincronia. Os dois são reconstruídos juntos no salvar,
    // a partir de quem está marcado — então não há como ficarem divergentes.
    testWidgets('incluir alguém no rateio: entra no digitado e nas cotas', (tester) async {
      final e2 = Expense.create(
        id: 'e5',
        description: 'Hotel',
        amount: 300,
        paidByPersonId: 'me',
        type: SplitType.weight,
        participantIds: const ['me', 'ana'],
        inputs: const {'me': 2, 'ana': 1},
        date: DateTime(2026, 1, 5),
      );
      await abrir(tester, e2);
      expect(camposDeRateio(tester), ['2', '1']);

      // Marca o Bruno e dá 3 partes a ele.
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(4), '3');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Salvar alterações'));
      await tester.pumpAndSettle();

      final salvo = ultimoSalvo(tester);
      expect(salvo.splitInputs, {'me': 2.0, 'ana': 1.0, 'bruno': 3.0});
      expect(salvo.shares.keys.toSet(), {'me', 'ana', 'bruno'});
      expect(salvo.shares.values.reduce((a, b) => a + b), 300.0);
    });

    testWidgets('tirar alguém do rateio: sai do digitado e das cotas', (tester) async {
      await abrir(tester, porPartes(valor: 360, partes: {'me': 3, 'ana': 2, 'bruno': 1}));

      await tester.tap(find.byType(Checkbox).at(2)); // desmarca Bruno
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar alterações'));
      await tester.pumpAndSettle();

      final salvo = ultimoSalvo(tester);
      expect(salvo.splitInputs, {'me': 3.0, 'ana': 2.0});
      expect(salvo.shares.containsKey('bruno'), isFalse);
      expect(salvo.shares.values.reduce((a, b) => a + b), 360.0);
    });

    testWidgets('quem saiu do grupo não volta pelo digitado', (tester) async {
      final comSaida = ExpenseGroup(
        id: 'g1',
        name: 'Viagem',
        emoji: '🏖️',
        createdAt: DateTime(2026, 1, 1),
        members: membros,
        removedMemberIds: const {'bruno'},
        expenses: [porPartes(valor: 360, partes: {'me': 3, 'ana': 2, 'bruno': 1})],
      );
      await abrirEm(tester, comSaida, comSaida.expenses.first);

      // Bruno saiu: nem aparece na folha, e o rateio já reabre só com os ativos.
      expect(camposDeRateio(tester), ['3', '2']);

      await tester.tap(find.text('Salvar alterações'));
      await tester.pumpAndSettle();
      final salvo = ultimoSalvo(tester);
      expect(salvo.splitInputs, {'me': 3.0, 'ana': 2.0});
      expect(salvo.shares.containsKey('bruno'), isFalse);
    });

    testWidgets('salvar com a divisão trocada pede confirmação', (tester) async {
      await abrir(tester, porPartes(valor: 360, partes: {'me': 3, 'ana': 2, 'bruno': 1}));
      await tester.tap(find.text(SplitType.equal.label));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Salvar alterações'));
      await tester.pumpAndSettle();

      expect(find.text('Mudar a divisão?'), findsOneWidget);
      expect(find.textContaining(SplitType.weight.label), findsWidgets);
    });
  });
}
