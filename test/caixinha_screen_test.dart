import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fechai/data/models/caixinha.dart';
import 'package:fechai/data/models/person.dart';
import 'package:fechai/data/repositories/app_repository.dart';
import 'package:fechai/data/repositories/in_memory_repository.dart';
import 'package:fechai/data/repositories/providers.dart';
import 'package:fechai/features/caixinha/caixinha_detail_screen.dart';

/// Repositório de teste: devolve uma caixinha fixa (sem delays), para montar a
/// tela de detalhe e conferir a estrutura de abas / permissões.
class _FakeRepo extends InMemoryRepository {
  final Caixinha fixture;
  _FakeRepo(this.fixture);

  @override
  Future<List<Caixinha>> caixinhas() async => [fixture];

  @override
  Future<Caixinha> caixinhaById(String id) async => fixture;
}

void main() {
  const me = Person(id: 'me', name: 'Você');
  const ana = Person(id: 'ana', name: 'Ana', lastName: 'Prado');

  Caixinha build({CaixinhaRole meuPapel = CaixinhaRole.owner}) => Caixinha(
        id: 'cx',
        name: 'Caixinha Teste',
        emoji: '🐷',
        ownerId: meuPapel == CaixinhaRole.owner ? 'me' : 'ana',
        defaultInterestPct: 10,
        monthlyQuota: 100,
        paymentDay: 5,
        createdAt: DateTime(2026, 1, 1),
        startDate: DateTime(2026, 1, 1),
        members: [
          CaixinhaMember(person: me, role: meuPapel),
          const CaixinhaMember(
            person: ana,
            role: CaixinhaRole.member,
            inviteStatus: MemberStatus.pending, // convidada, ainda sem aceite
          ),
        ],
        contributions: [
          Contribution(id: 'c1', personId: 'me', amount: 100, date: DateTime(2026, 1, 5)),
        ],
      );

  Future<void> pump(WidgetTester tester, Caixinha c) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRepositoryProvider.overrideWithValue(_FakeRepo(c) as AppRepository)],
        child: const MaterialApp(home: CaixinhaDetailScreen(caixinhaId: 'cx')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tela abre em abas, sem exceções', (tester) async {
    await pump(tester, build());
    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Quitação'), findsOneWidget);
    expect(find.text('Empréstimos'), findsOneWidget);
    expect(find.text('Histórico'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dono vê o botão de lançar com as três ações', (tester) async {
    await pump(tester, build());
    expect(find.text('Lançar'), findsOneWidget);
    await tester.tap(find.text('Lançar'));
    await tester.pumpAndSettle();
    expect(find.text('Aporte'), findsOneWidget);
    expect(find.text('Rendimento'), findsOneWidget);
    expect(find.text('Emprestar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('membro comum NÃO vê o botão de lançar', (tester) async {
    await pump(tester, build(meuPapel: CaixinhaRole.member));
    expect(find.text('Lançar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aba Quitação lista participante convidado (sem aceite) com sobrenome', (tester) async {
    await pump(tester, build());
    await tester.tap(find.text('Quitação'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Prado'), findsWidgets); // nome + sobrenome
    expect(tester.takeException(), isNull);
  });

  testWidgets('aba Histórico mostra o extrato com saldo antes → depois', (tester) async {
    await pump(tester, build());
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aporte'), findsWidgets);
    expect(find.text('Patrimônio'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
