import 'package:flutter_test/flutter_test.dart';
import 'package:fechai/data/models/caixinha.dart';
import 'package:fechai/data/models/person.dart';
import 'package:fechai/data/repositories/in_memory_repository.dart';

/// Trava a matemática de participação (unidade × tempo) da Caixinha com o
/// cenário validado na mão: Ana e Bruno entram no mês 1, Carlos entra no mês 2,
/// e um empréstimo à Fernanda (10%/mês) rende R$100/mês. Justiça esperada: os
/// três aportam R$2.000, mas Carlos recebe menos por ter entrado depois.
void main() {
  const ana = Person(id: 'ana', name: 'Ana');
  const bruno = Person(id: 'bruno', name: 'Bruno');
  const carlos = Person(id: 'carlos', name: 'Carlos');
  const fernanda = Person(id: 'fernanda', name: 'Fernanda');

  Caixinha build({List<LoanPayment> payments = const []}) => Caixinha(
        id: 'c1',
        name: 'Caixinha da Família',
        emoji: '🐷',
        defaultInterestPct: 10,
        monthlyQuota: 2000,
        createdAt: DateTime(2026, 1, 1),
        members: const [
          CaixinhaMember(person: ana, role: CaixinhaRole.owner),
          CaixinhaMember(person: bruno, role: CaixinhaRole.member),
          CaixinhaMember(person: carlos, role: CaixinhaRole.member),
          CaixinhaMember(person: fernanda, role: CaixinhaRole.borrower),
        ],
        contributions: [
          Contribution(id: 'a1', personId: 'ana', amount: 2000, date: DateTime(2026, 1, 1)),
          Contribution(id: 'b1', personId: 'bruno', amount: 2000, date: DateTime(2026, 1, 1)),
          Contribution(id: 'c2', personId: 'carlos', amount: 2000, date: DateTime(2026, 2, 1)),
        ],
        loans: [
          Loan(id: 'l1', borrowerName: 'Fernanda', borrowerPersonId: 'fernanda', principal: 1000, interestPct: 10, date: DateTime(2026, 1, 5)),
        ],
        earnings: [
          Earning(id: 'j1', amount: 100, source: EarningSource.loanInterest, date: DateTime(2026, 1, 31), loanId: 'l1'),
          Earning(id: 'j2', amount: 100, source: EarningSource.loanInterest, date: DateTime(2026, 2, 28), loanId: 'l1'),
        ],
        loanPayments: payments,
      );

  group('Participação por unidade × tempo', () {
    final c = build();

    test('patrimônio = aportes + rendimentos', () {
      expect(c.patrimony, 6200.0); // 6000 aportado + 200 de juros
    });

    test('cada um recebe sua fatia e a soma fecha o patrimônio', () {
      expect(c.balanceOf('ana'), closeTo(2083.6, 0.5));
      expect(c.balanceOf('bruno'), closeTo(2083.6, 0.5));
      expect(c.balanceOf('carlos'), closeTo(2032.8, 0.5));
      final soma = c.balanceOf('ana') + c.balanceOf('bruno') + c.balanceOf('carlos');
      expect(soma, closeTo(6200.0, 0.01));
    });

    test('justiça: quem entrou junto ganha igual; quem entrou depois ganha menos', () {
      expect(c.balanceOf('ana'), closeTo(c.balanceOf('bruno'), 0.001));
      expect(c.balanceOf('carlos'), lessThan(c.balanceOf('ana')));
    });

    test('tomador externo não participa da partilha', () {
      expect(c.participationOf('fernanda'), 0);
      expect(c.balanceOf('fernanda'), 0);
      expect(c.acceptedMembersCount, 3); // externo não conta
      expect(c.contributingMembers.length, 3);
      expect(c.borrowers.length, 1);
    });

    test('participações somam 100%', () {
      final total = c.participationOf('ana') + c.participationOf('bruno') + c.participationOf('carlos');
      expect(total, closeTo(1.0, 0.0001));
    });
  });

  group('Projeção (estimativa)', () {
    test('sem juros, é só a soma dos aportes', () {
      final p = CaixinhaProjection.simulate(
        startBalance: 0,
        participants: 3,
        monthlyContribution: 100,
        months: 12,
        monthlyRatePct: 0,
      );
      expect(p.totalContributed, 3600.0); // 3 × 100 × 12
      expect(p.projectedTotal, 3600.0);
      expect(p.estimatedYield, 0.0);
      expect(p.perParticipant, closeTo(1200.0, 0.01));
    });

    test('com juros, o total projetado supera o aportado', () {
      final p = CaixinhaProjection.simulate(
        startBalance: 1000,
        participants: 2,
        monthlyContribution: 200,
        months: 6,
        monthlyRatePct: 1,
      );
      expect(p.totalContributed, closeTo(1000 + 400 * 6, 0.01)); // 3400
      expect(p.projectedTotal, greaterThan(p.totalContributed));
      expect(p.estimatedYield, closeTo(p.projectedTotal - p.totalContributed, 0.01));
    });
  });

  group('Saída de participante (devolve só o aportado)', () {
    Caixinha withExit(List<MemberExit> exits) => Caixinha(
          id: 'c2',
          name: 'Teste saída',
          emoji: '🐷',
          createdAt: DateTime(2026, 1, 1),
          members: const [
            CaixinhaMember(person: ana, role: CaixinhaRole.owner),
            CaixinhaMember(person: bruno, role: CaixinhaRole.member),
          ],
          contributions: [
            Contribution(id: 'x1', personId: 'ana', amount: 2000, date: DateTime(2026, 1, 1)),
            Contribution(id: 'x2', personId: 'bruno', amount: 2000, date: DateTime(2026, 1, 1)),
          ],
          earnings: [
            Earning(id: 'e', amount: 100, source: EarningSource.investment, date: DateTime(2026, 1, 31)),
          ],
          exits: exits,
        );

    test('quem sai leva só o que aportou; o lucro fica para quem continua', () {
      final c = withExit([
        MemberExit(id: 'ex1', memberId: 'bruno', refund: 2000, date: DateTime(2026, 2, 1)),
      ]);
      expect(c.patrimony, 2100.0); // 4000 aportado + 100 rendido - 2000 devolvido
      expect(c.hasExited('bruno'), isTrue);
      expect(c.exitRefundOf('bruno'), 2000.0);
      expect(c.participationOf('bruno'), 0);
      expect(c.balanceOf('bruno'), 0);
      // Ana fica com 100% e herda o lucro que o Bruno deixou (ela sai de 2050 p/ 2100).
      expect(c.participationOf('ana'), closeTo(1.0, 0.0001));
      expect(c.balanceOf('ana'), closeTo(2100.0, 0.01));
      expect(c.contributingMembers.length, 1);
      expect(c.exitedMembers.length, 1);
    });
  });

  group('Onboarding — caixinha já em andamento', () {
    test('saldo atual vira aporte semente; participação e papéis corretos', () async {
      final repo = InMemoryRepository();
      const ana = Person(id: 'x_ana', name: 'Ana');
      const bruno = Person(id: 'x_bruno', name: 'Bruno');
      final c = await repo.createCaixinha(
        name: 'Migrada',
        emoji: '🐷',
        defaultInterestPct: 10,
        monthlyQuota: 100,
        members: [ana, bruno],
        openingBalances: {'me': 3000, 'x_ana': 1000, 'x_bruno': 0},
        treasurers: {'x_ana'},
      );
      // Bruno com saldo 0 não gera aporte semente.
      expect(c.contributions.length, 2);
      expect(c.patrimony, 4000.0);
      expect(c.participationOf('me'), closeTo(0.75, 0.001));
      expect(c.participationOf('x_ana'), closeTo(0.25, 0.001));
      expect(c.participationOf('x_bruno'), 0);
      // Papéis: dono, tesoureira eleita, membro comum.
      expect(c.memberById('me')!.role, CaixinhaRole.owner);
      expect(c.memberById('x_ana')!.role, CaixinhaRole.treasurer);
      expect(c.memberById('x_bruno')!.role, CaixinhaRole.member);
      expect(c.isTreasurer('x_ana'), isTrue);
      expect(c.isTreasurer('x_bruno'), isFalse);
    });

    test('sem saldos (do zero) não semeia aportes', () async {
      final repo = InMemoryRepository();
      const ana = Person(id: 'y_ana', name: 'Ana');
      final c = await repo.createCaixinha(
        name: 'Nova',
        emoji: '🐷',
        defaultInterestPct: 10,
        monthlyQuota: 100,
        members: [ana],
      );
      expect(c.contributions, isEmpty);
      expect(c.patrimony, 0.0);
    });
  });

  group('Leva 2 — projeção por pessoa, cota pendente, juros retroativos', () {
    Caixinha base({List<Contribution> contribs = const []}) => Caixinha(
          id: 'l2',
          name: 'L2',
          emoji: '🐷',
          monthlyQuota: 100,
          createdAt: DateTime(2026, 1, 1),
          members: const [
            CaixinhaMember(person: ana, role: CaixinhaRole.owner),
            CaixinhaMember(person: bruno, role: CaixinhaRole.member),
          ],
          contributions: contribs,
        );

    test('projeção sem juros = soma dos aportes; somas por pessoa batem', () {
      final c = base(contribs: [
        Contribution(id: 'a', personId: 'ana', amount: 1000, date: DateTime(2026, 1, 1)),
      ]);
      final p = c.project(months: 12, monthlyRatePct: 0);
      // Ana e Bruno aportam 100/mês por 12 meses. Ana já tinha 1000.
      expect(p.totalContributed, closeTo(1000 + 100 * 12 + 100 * 12, 0.01)); // 3400
      expect(p.totalProjected, closeTo(p.totalContributed, 0.01)); // 0% juros
      final somaPessoas = p.people.fold(0.0, (a, x) => a + x.projected);
      expect(somaPessoas, closeTo(p.totalProjected, 0.01));
    });

    test('projeção com juros rende (projetado > aportado)', () {
      final c = base(contribs: [Contribution(id: 'a', personId: 'ana', amount: 1000, date: DateTime(2026, 1, 1))]);
      final p = c.project(months: 6, monthlyRatePct: 1);
      expect(p.totalProjected, greaterThan(p.totalContributed));
      expect(p.totalYield, closeTo(p.totalProjected - p.totalContributed, 0.01));
    });

    test('cota pendente do mês', () {
      final ref = DateTime(2026, 3, 15);
      final c = base(contribs: [
        Contribution(id: 'x', personId: 'ana', amount: 40, date: DateTime(2026, 3, 2)), // pagou parcial
      ]);
      expect(c.cotaPendingThisMonth('ana', ref), closeTo(60.0, 0.01)); // 100 - 40
      expect(c.cotaPendingThisMonth('bruno', ref), closeTo(100.0, 0.01)); // não pagou
      // Mês seguinte: ninguém pagou ainda.
      expect(c.cotaPendingThisMonth('ana', DateTime(2026, 4, 1)), closeTo(100.0, 0.01));
    });

    test('juros retroativos: um lançamento cheio por mês decorrido', () {
      final j = retroactiveLoanInterest(
        loanDate: DateTime(2026, 1, 10),
        principal: 500,
        interestPct: 10,
        now: DateTime(2026, 4, 15),
      );
      expect(j.length, 3); // jan→abr = 3 meses
      expect(j.every((e) => e.amount == 50.0), isTrue);
      // Empréstimo no mês corrente ainda não rendeu.
      expect(retroactiveLoanInterest(loanDate: DateTime(2026, 4, 1), principal: 500, interestPct: 10, now: DateTime(2026, 4, 20)), isEmpty);
    });
  });

  group('Cenário complexo — invariantes de consistência', () {
    const duda = Person(id: 'duda', name: 'Duda');

    // Linha do tempo (2026): entradas em datas diferentes, rendimentos de
    // investimento e de juros, empréstimo externo com pagamento parcial, e uma
    // saída no meio. Números escolhidos para conferência à mão.
    final c = Caixinha(
      id: 'cx',
      name: 'Complexa',
      emoji: '🐷',
      defaultInterestPct: 10,
      monthlyQuota: 500,
      createdAt: DateTime(2026, 1, 1),
      members: const [
        CaixinhaMember(person: ana, role: CaixinhaRole.owner),
        CaixinhaMember(person: bruno, role: CaixinhaRole.member),
        CaixinhaMember(person: carlos, role: CaixinhaRole.member),
        CaixinhaMember(person: duda, role: CaixinhaRole.member),
        CaixinhaMember(person: fernanda, role: CaixinhaRole.borrower),
      ],
      contributions: [
        Contribution(id: 'a1', personId: 'ana', amount: 1000, date: DateTime(2026, 1, 5)),
        Contribution(id: 'b1', personId: 'bruno', amount: 500, date: DateTime(2026, 1, 5)),
        Contribution(id: 'c1', personId: 'carlos', amount: 800, date: DateTime(2026, 2, 3)),
        Contribution(id: 'd1', personId: 'duda', amount: 600, date: DateTime(2026, 3, 1)),
        Contribution(id: 'a2', personId: 'ana', amount: 1000, date: DateTime(2026, 4, 1)),
      ],
      earnings: [
        Earning(id: 'i1', amount: 30, source: EarningSource.investment, date: DateTime(2026, 1, 31)),
        Earning(id: 'j1', amount: 40, source: EarningSource.loanInterest, loanId: 'lF', date: DateTime(2026, 2, 28)),
        Earning(id: 'j2', amount: 40, source: EarningSource.loanInterest, loanId: 'lF', date: DateTime(2026, 3, 31)),
      ],
      loans: [
        Loan(id: 'lF', borrowerName: 'Fernanda', borrowerPersonId: 'fernanda', principal: 400, interestPct: 10, date: DateTime(2026, 2, 10)),
      ],
      loanPayments: [
        LoanPayment(id: 'p1', loanId: 'lF', amount: 200, date: DateTime(2026, 3, 10)),
      ],
      exits: [
        MemberExit(id: 'e1', memberId: 'bruno', refund: 500, date: DateTime(2026, 3, 2)),
      ],
    );

    // Cálculo de caixa independente (fórmula alternativa) para cruzar.
    double independentCash() {
      final contrib = c.contributions.fold(0.0, (a, x) => a + x.amount);
      final invest = c.earnings.where((e) => e.source == EarningSource.investment).fold(0.0, (a, e) => a + e.amount);
      final principal = c.loans.fold(0.0, (a, l) => a + l.principal);
      final repaid = c.loanPayments.fold(0.0, (a, p) => a + p.amount);
      final refunds = c.exits.fold(0.0, (a, x) => a + x.refund);
      return contrib + invest - principal + repaid - refunds;
    }

    test('patrimônio = aportes + rendimentos − reembolsos', () {
      expect(c.totalContributed, 3900.0);
      expect(c.totalEarnings, 110.0);
      expect(c.totalRefunds, 500.0);
      expect(c.patrimony, 3510.0);
    });

    test('conservação: patrimônio + reembolsos = aportes + rendimentos', () {
      expect(c.patrimony + c.totalRefunds, closeTo(c.totalContributed + c.totalEarnings, 0.001));
    });

    test('saldo do empréstimo = principal + juros − pago', () {
      expect(c.outstandingOf(c.loans.first), 280.0); // 400 + 80 − 200
      expect(c.outstandingReceivables, 280.0);
    });

    test('caixa = patrimônio − a receber, e bate com a fórmula independente', () {
      expect(c.cashOnHand, closeTo(3230.0, 0.001));
      expect(c.cashOnHand, closeTo(independentCash(), 0.001));
    });

    test('soma das partes de todos = patrimônio', () {
      final soma = c.members.fold(0.0, (a, m) => a + c.balanceOf(m.person.id));
      expect(soma, closeTo(c.patrimony, 0.01));
    });

    test('quem saiu e o externo têm participação zero', () {
      expect(c.participationOf('bruno'), 0);
      expect(c.balanceOf('bruno'), 0);
      expect(c.participationOf('fernanda'), 0);
    });

    test('participações dos ativos somam 100%', () {
      final soma = c.participationOf('ana') + c.participationOf('carlos') + c.participationOf('duda');
      expect(soma, closeTo(1.0, 0.0001));
    });

    test('listas de membros refletem papéis e saída', () {
      expect(c.memberCount, 3); // ana, carlos, duda (bruno saiu; fernanda é externa)
      expect(c.contributingMembers.map((m) => m.person.id).toSet(), {'ana', 'carlos', 'duda'});
      expect(c.exitedMembers.map((m) => m.person.id), ['bruno']);
      expect(c.borrowers.map((m) => m.person.id), ['fernanda']);
    });

    test('lucro só existe para quem ficou (soma dos lucros dos ativos = rendimento retido)', () {
      // Rendimento total 110; o Bruno saiu levando só o aportado (não levou lucro).
      // Logo todo o rendimento fica com os ativos.
      final lucroAtivos = c.profitOf('ana') + c.profitOf('carlos') + c.profitOf('duda');
      expect(lucroAtivos, closeTo(110.0, 0.01));
    });
  });

  group('Ajuste manual + histórico', () {
    final c = Caixinha(
      id: 'caj',
      name: 'Ajuste',
      emoji: '🐷',
      createdAt: DateTime(2026, 1, 1),
      members: const [
        CaixinhaMember(person: ana, role: CaixinhaRole.owner),
        CaixinhaMember(person: bruno, role: CaixinhaRole.member),
      ],
      contributions: [
        Contribution(id: 'a', personId: 'ana', amount: 1000, date: DateTime(2026, 1, 1)),
        Contribution(id: 'b', personId: 'bruno', amount: 1000, date: DateTime(2026, 1, 1)),
      ],
      adjustments: [
        Adjustment(id: 'aj', memberId: 'ana', delta: 200, note: 'Correção', date: DateTime(2026, 2, 1)),
      ],
    );

    test('ajuste muda o saldo da pessoa e o patrimônio no mesmo valor', () {
      expect(c.patrimony, 2200.0);
      expect(c.balanceOf('ana'), closeTo(1200.0, 0.01));
      expect(c.balanceOf('bruno'), closeTo(1000.0, 0.01));
      expect(c.adjustedBy('ana'), 200.0);
      expect(c.refundBaseOf('ana'), 1200.0); // 1000 aportado + 200 ajuste
    });

    test('histórico traz as movimentações com o saldo acumulado', () {
      final mv = c.movements;
      expect(mv.length, 3); // 2 aportes + 1 ajuste
      expect(mv.first.balanceAfter, 1000.0);
      expect(mv[1].balanceAfter, 2000.0);
      expect(mv.last.kind, MovementKind.adjustment);
      expect(mv.last.amount, 200.0);
      expect(mv.last.balanceAfter, 2200.0); // fecha no patrimônio
    });
  });

  group('Perda / prejuízo (rendimento negativo)', () {
    test('perda global baixa o saldo de todos proporcionalmente', () {
      final c = Caixinha(
        id: 'perda',
        name: 'P',
        emoji: '🐷',
        createdAt: DateTime(2026, 1, 1),
        members: const [
          CaixinhaMember(person: ana, role: CaixinhaRole.owner),
          CaixinhaMember(person: bruno, role: CaixinhaRole.member),
        ],
        contributions: [
          Contribution(id: 'a', personId: 'ana', amount: 1000, date: DateTime(2026, 1, 1)),
          Contribution(id: 'b', personId: 'bruno', amount: 1000, date: DateTime(2026, 1, 1)),
        ],
        earnings: [
          Earning(id: 'e', amount: -200, source: EarningSource.investment, date: DateTime(2026, 2, 1)),
        ],
      );
      expect(c.patrimony, 1800.0);
      expect(c.balanceOf('ana'), closeTo(900.0, 0.01));
      expect(c.balanceOf('bruno'), closeTo(900.0, 0.01));
    });

    test('calote (marcar como perda) zera o a receber e baixa o patrimônio', () {
      final c = Caixinha(
        id: 'calote',
        name: 'C',
        emoji: '🐷',
        createdAt: DateTime(2026, 1, 1),
        members: const [
          CaixinhaMember(person: ana, role: CaixinhaRole.owner),
          CaixinhaMember(person: bruno, role: CaixinhaRole.member),
          CaixinhaMember(person: fernanda, role: CaixinhaRole.borrower),
        ],
        contributions: [
          Contribution(id: 'a', personId: 'ana', amount: 2000, date: DateTime(2026, 1, 1)),
          Contribution(id: 'b', personId: 'bruno', amount: 2000, date: DateTime(2026, 1, 1)),
        ],
        loans: [
          Loan(id: 'l', borrowerName: 'Fernanda', borrowerPersonId: 'fernanda', principal: 1000, interestPct: 10, date: DateTime(2026, 1, 5)),
        ],
        earnings: [
          Earning(id: 'j', amount: 100, source: EarningSource.loanInterest, loanId: 'l', date: DateTime(2026, 1, 31)),
          // Marcar como perda = rendimento negativo do saldo devedor (1100) amarrado ao empréstimo.
          Earning(id: 'perda', amount: -1100, source: EarningSource.loanInterest, loanId: 'l', date: DateTime(2026, 2, 1)),
        ],
      );
      final loan = c.loans.first;
      expect(c.isWrittenOff(loan), isTrue);
      expect(c.outstandingOf(loan), 0.0); // some do "a receber"
      expect(c.outstandingReceivables, 0.0);
      expect(c.patrimony, 3000.0); // 4000 + 100 - 1100
      // A perda (1100) foi dividida entre Ana e Bruno.
      expect(c.balanceOf('ana'), closeTo(1500.0, 0.01));
      expect(c.balanceOf('bruno'), closeTo(1500.0, 0.01));
      expect(c.cashOnHand, closeTo(3000.0, 0.01));
    });
  });

  group('Rendimento é mensal (dia do aporte não importa)', () {
    // Ana aporta dia 1, rendimento dia 10, Bruno aporta dia 20 — tudo no mesmo
    // mês. Ambos pagaram a cota do mês, então dividem o rendimento igualmente.
    final c = Caixinha(
      id: 'cm',
      name: 'Mensal',
      emoji: '🐷',
      createdAt: DateTime(2026, 1, 1),
      members: const [
        CaixinhaMember(person: ana, role: CaixinhaRole.owner),
        CaixinhaMember(person: bruno, role: CaixinhaRole.member),
      ],
      contributions: [
        Contribution(id: 'a', personId: 'ana', amount: 1000, date: DateTime(2026, 1, 1)),
        Contribution(id: 'b', personId: 'bruno', amount: 1000, date: DateTime(2026, 1, 20)),
      ],
      earnings: [
        Earning(id: 'e', amount: 200, source: EarningSource.investment, date: DateTime(2026, 1, 10)),
      ],
    );

    test('mesmo mês, cotas iguais → partes iguais (independe do dia)', () {
      expect(c.balanceOf('ana'), closeTo(1100.0, 0.01));
      expect(c.balanceOf('bruno'), closeTo(1100.0, 0.01));
      expect(c.balanceOf('ana'), closeTo(c.balanceOf('bruno'), 0.001));
    });
  });

  group('Empréstimo: saldo, quitação parcial e total', () {
    final loan = build().loans.first;

    test('sem pagamento, deve principal + juros e fica fora do caixa', () {
      final c = build();
      expect(c.outstandingOf(loan), 1200.0); // 1000 + 200 juros
      expect(c.isSettled(loan), isFalse);
      expect(c.cashOnHand, closeTo(5000.0, 0.01)); // 6200 - 1200
    });

    test('quitação parcial reduz o saldo e devolve parte ao caixa', () {
      final c = build(payments: [
        LoanPayment(id: 'p1', loanId: 'l1', amount: 500, date: DateTime(2026, 3, 1)),
      ]);
      expect(c.outstandingOf(loan), 700.0); // 1200 - 500
      expect(c.isSettled(loan), isFalse); // ainda deve
      expect(c.cashOnHand, closeTo(5500.0, 0.01)); // 6200 - 700
      expect(c.patrimony, 6200.0); // patrimônio não muda ao receber pagamento
    });

    test('pagando o saldo todo, empréstimo é quitado e some do "a receber"', () {
      final c = build(payments: [
        LoanPayment(id: 'p1', loanId: 'l1', amount: 700, date: DateTime(2026, 3, 1)),
        LoanPayment(id: 'p2', loanId: 'l1', amount: 500, date: DateTime(2026, 4, 1)),
      ]);
      expect(c.outstandingOf(loan), 0.0);
      expect(c.isSettled(loan), isTrue);
      expect(c.openLoans, isEmpty);
      expect(c.cashOnHand, closeTo(6200.0, 0.01));
    });
  });

  group('Cotas por mês — meses com pendência (por papel)', () {
    const me = Person(id: 'me', name: 'Você');
    // Eu pago jan e fev; Bruno só jan. mês atual = mar/2026.
    final c = Caixinha(
      id: 'pend',
      name: 'Pend',
      emoji: '🐷',
      monthlyQuota: 100,
      createdAt: DateTime(2026, 1, 1),
      members: const [
        CaixinhaMember(person: me, role: CaixinhaRole.owner),
        CaixinhaMember(person: bruno, role: CaixinhaRole.member),
      ],
      contributions: [
        Contribution(id: 'm1', personId: 'me', amount: 100, date: DateTime(2026, 1, 10)),
        Contribution(id: 'm2', personId: 'me', amount: 100, date: DateTime(2026, 2, 10)),
        Contribution(id: 'b1', personId: 'bruno', amount: 100, date: DateTime(2026, 1, 10)),
      ],
    );
    final now = DateTime(2026, 3, 15);

    test('só as próprias pendências: falta só março', () {
      final meses = c.monthsWithPendencies(onlyMe: true, now: now);
      expect(meses.map((d) => d.month), [3]);
    });

    test('visão de tesoureiro: qualquer pendência (fev do Bruno + março de todos)', () {
      final meses = c.monthsWithPendencies(onlyMe: false, now: now);
      expect(meses.map((d) => d.month), [2, 3]);
    });

    test('sem cota definida não há meses com pendência', () {
      final semCota = Caixinha(
        id: 'nq', name: 'NQ', emoji: '🐷', createdAt: DateTime(2026, 1, 1),
        members: const [CaixinhaMember(person: me, role: CaixinhaRole.owner)],
      );
      expect(semCota.monthsWithPendencies(onlyMe: true, now: now), isEmpty);
    });
  });

  group('Série mensal do gráfico (com × sem rendimento + projeção)', () {
    const me = Person(id: 'me', name: 'Você');
    final c = Caixinha(
      id: 'serie',
      name: 'Série',
      emoji: '🐷',
      monthlyQuota: 0,
      createdAt: DateTime(2026, 1, 1),
      members: const [CaixinhaMember(person: me, role: CaixinhaRole.owner)],
      contributions: [Contribution(id: 'c1', personId: 'me', amount: 1000, date: DateTime(2026, 1, 5))],
      earnings: [Earning(id: 'e1', amount: 100, source: EarningSource.investment, date: DateTime(2026, 2, 3))],
    );

    test('pontos reais: aportado constante, patrimônio sobe com o rendimento', () {
      final s = c.monthlySeries(now: DateTime(2026, 2, 15), projectMonths: 6, projectionRatePct: 0.5);
      final real = s.where((p) => !p.projected).toList();
      expect(real.length, 2);
      expect(real[0].contributed, closeTo(1000, 0.01));
      expect(real[0].patrimony, closeTo(1000, 0.01));
      expect(real[1].contributed, closeTo(1000, 0.01)); // rendimento não entra no "sem rendimento"
      expect(real[1].patrimony, closeTo(1100, 0.01));
      expect(real.last.patrimony, closeTo(c.patrimony, 0.01));
    });

    test('projeção acrescenta meses futuros que crescem com juros', () {
      final s = c.monthlySeries(now: DateTime(2026, 2, 15), projectMonths: 6, projectionRatePct: 0.5);
      final proj = s.where((p) => p.projected).toList();
      expect(proj.length, 6);
      expect(proj.first.patrimony, closeTo(1100 * 1.005, 0.01));
      expect(s.last.patrimony, greaterThan(1100));
    });
  });

  group('Atraso de cota com juros (compostos, tipo empréstimo)', () {
    const me = Person(id: 'me', name: 'Você');
    Caixinha build({List<Contribution> contribs = const [], int? day = 5}) => Caixinha(
          id: 'atr',
          name: 'Atraso',
          emoji: '🐷',
          defaultInterestPct: 10,
          monthlyQuota: 100,
          paymentDay: day,
          createdAt: DateTime(2026, 1, 1),
          members: const [CaixinhaMember(person: me, role: CaixinhaRole.owner)],
          contributions: contribs,
        );

    test('3 meses vencidos sem pagar: principal soma e juros compõem', () {
      final c = build();
      final a = c.cotaArrearsOf('me', now: DateTime(2026, 3, 10));
      expect(a.months, 3);
      expect(a.principal, closeTo(300, 0.01)); // 3 × 100
      expect(a.interest, closeTo(31, 0.01)); // jan sem juros; fev +10; mar +21
      expect(a.total, closeTo(331, 0.01));
      expect(a.oldestDue, DateTime(2026, 1));
    });

    test('pagar um mês vencido tira ele do atraso', () {
      final c = build(contribs: [Contribution(id: 'j', personId: 'me', amount: 100, date: DateTime(2026, 1, 5))]);
      final overdue = c.overdueMonths('me', now: DateTime(2026, 3, 10));
      expect(overdue.map((e) => e.month.month), [2, 3]);
      final a = c.cotaArrearsOf('me', now: DateTime(2026, 3, 10));
      expect(a.months, 2);
      expect(a.principal, closeTo(200, 0.01));
      expect(a.interest, closeTo(10, 0.01)); // fev sem juros (1º vencido); mar +10
    });

    test('cota do mês ainda não vencida não entra no atraso', () {
      final c = build();
      // Antes do dia 5 de janeiro: nada venceu ainda.
      final a = c.cotaArrearsOf('me', now: DateTime(2026, 1, 3));
      expect(a.isLate, isFalse);
      expect(c.overdueMonths('me', now: DateTime(2026, 1, 3)), isEmpty);
    });

    test('sem dia de pagamento não há atraso com juros', () {
      final c = build(day: null);
      expect(c.cotaArrearsOf('me', now: DateTime(2026, 6, 1)).isLate, isFalse);
      expect(c.overdueMonths('me', now: DateTime(2026, 6, 1)), isEmpty);
    });
  });

  group('Quitação parcial — o juro devido nunca some', () {
    const me = Person(id: 'me', name: 'Você');
    final agora = DateTime(2026, 4, 10); // jan..abr vencidos (dia 5)

    Caixinha build({
      List<Contribution> contribs = const [],
      List<CotaInterestCharge> charges = const [],
    }) =>
        Caixinha(
          id: 'q',
          name: 'Q',
          emoji: '🐷',
          defaultInterestPct: 10,
          monthlyQuota: 100,
          paymentDay: 5,
          createdAt: DateTime(2026, 1, 1),
          members: const [CaixinhaMember(person: me, role: CaixinhaRole.owner)],
          contributions: contribs,
          cotaCharges: charges,
        );

    /// Aplica um plano (como a UI faz) e devolve a caixinha resultante.
    Caixinha apply(Caixinha c, CotaSettlementPlan p, {String pid = 'me'}) {
      final pagos = {for (final cp in p.chargePayments) cp.chargeId: cp.amount};
      return c.copyWith(
        contributions: [
          ...c.contributions,
          for (final f in p.fills)
            Contribution(id: 'f${f.month.month}', personId: pid, amount: f.amount, date: c.dueDateOfMonth(f.month)),
        ],
        cotaCharges: [
          for (final ch in c.cotaCharges)
            if (pagos.containsKey(ch.id))
              CotaInterestCharge(
                id: ch.id,
                memberId: ch.memberId,
                amount: ch.amount,
                paidAmount: ch.paidAmount + pagos[ch.id]!,
                date: ch.date,
              )
            else
              ch,
          if (p.newCharge > 0.005)
            CotaInterestCharge(id: 'novo', memberId: pid, amount: p.newCharge, date: agora),
        ],
      );
    }

    test('cenário base: 4 meses vencidos com juros compostos', () {
      final a = build().cotaArrearsOf('me', now: agora);
      expect(a.principal, closeTo(400, 0.01));
      expect(a.interest, closeTo(64.10, 0.01)); // 0 + 10 + 21 + 33,10
      expect(a.carriedInterest, 0);
    });

    test('pagar exatamente a cota do mês mais antigo NÃO apaga o juro dele', () {
      final c = build();
      final antes = c.cotaArrearsOf('me', now: agora);
      final plan = c.planCotaSettlement('me', amount: 100, now: agora);

      // O juro que deixou de ser derivável foi cristalizado, não perdido.
      expect(plan.monthsCleared, 1);
      expect(plan.interestPaid, 0);
      expect(plan.freedInterest, closeTo(33.10, 0.01));
      expect(plan.newCharge, closeTo(33.10, 0.01));

      final depois = apply(c, plan).cotaArrearsOf('me', now: agora);
      expect(depois.carriedInterest, closeTo(33.10, 0.01)); // segue no radar
      // INVARIANTE: a dívida cai exatamente o que foi pago.
      expect(depois.total, closeTo(antes.total - 100, 0.01));
    });

    test('invariante da conservação vale para vários valores parciais', () {
      for (final valor in [50.0, 100.0, 150.0, 233.33, 400.0]) {
        final c = build();
        final antes = c.cotaArrearsOf('me', now: agora).total;
        final plan = c.planCotaSettlement('me', amount: valor, now: agora);
        final depois = apply(c, plan).cotaArrearsOf('me', now: agora).total;
        expect(depois, closeTo(antes - valor, 0.01), reason: 'pagando $valor');
        expect(plan.remainingDebt, closeTo(depois, 0.01), reason: 'prévia bate com o real ($valor)');
      }
    });

    test('pagamento parcial de uma cota deixa o resto na própria cota', () {
      final c = build();
      final plan = c.planCotaSettlement('me', amount: 150, now: agora);
      expect(plan.monthsCleared, 1); // jan inteiro
      expect(plan.partialMonth, DateTime(2026, 1).month == 1 ? DateTime(2026, 2) : null);
      expect(plan.partialAmount, closeTo(50, 0.01)); // 50 dos 100 de fevereiro
      final depois = apply(c, plan);
      // Fevereiro continua vencido, agora devendo só 50.
      final fev = depois.overdueMonths('me', now: agora).firstWhere((e) => e.month.month == 2);
      expect(fev.shortfall, closeTo(50, 0.01));
    });

    test('pagar tudo zera a dívida e não cristaliza nada', () {
      final c = build();
      final total = c.cotaArrearsOf('me', now: agora).total;
      final plan = c.planCotaSettlement('me', amount: total, now: agora);
      expect(plan.interestPaid, closeTo(64.10, 0.01)); // vira rendimento
      expect(plan.newCharge, 0);
      final depois = apply(c, plan).cotaArrearsOf('me', now: agora);
      expect(depois.isLate, isFalse);
    });

    test('"pagou em dia" corrige o registro sem cobrar juros', () {
      final c = build();
      final plan = c.planCotaSettlement('me', amount: 100, chargeInterest: false, now: agora);
      expect(plan.interestPaid, 0);
      expect(plan.newCharge, 0); // perdoa (é correção, não cobrança)
      final depois = apply(c, plan).cotaArrearsOf('me', now: agora);
      expect(depois.principal, closeTo(300, 0.01));
      expect(depois.interest, closeTo(31, 0.01));
      expect(depois.carriedInterest, 0);
    });

    test('juro cristalizado é cobrado antes do novo e some ao ser pago', () {
      final c = build(charges: [
        CotaInterestCharge(id: 'velho', memberId: 'me', amount: 20, date: DateTime(2026, 3, 1)),
      ]);
      expect(c.cotaArrearsOf('me', now: agora).carriedInterest, closeTo(20, 0.01));
      // Paga as 4 cotas (400) + 20 do juro velho.
      final plan = c.planCotaSettlement('me', amount: 420, now: agora);
      expect(plan.chargePayments.single.chargeId, 'velho');
      expect(plan.chargePayments.single.amount, closeTo(20, 0.01));
      final depois = apply(c, plan);
      // O juro velho foi quitado; sobra só o que acabou de ser cristalizado.
      expect(depois.cotaCharges.firstWhere((x) => x.id == 'velho').isSettled, isTrue);
      expect(depois.carriedInterestOf('me'), closeTo(plan.newCharge, 0.01));
    });

    test('sem cota/vencimento, juro cristalizado continua devido', () {
      final c = Caixinha(
        id: 'sc', name: 'SC', emoji: '🐷',
        createdAt: DateTime(2026, 1, 1),
        members: const [CaixinhaMember(person: me, role: CaixinhaRole.owner)],
        cotaCharges: [CotaInterestCharge(id: 'x', memberId: 'me', amount: 15, date: DateTime(2026, 2, 1))],
      );
      final a = c.cotaArrearsOf('me', now: agora);
      expect(a.isLate, isTrue);
      expect(a.interest, closeTo(15, 0.01));
      expect(a.carriedInterest, closeTo(15, 0.01));
    });
  });

  group('Gráfico — projeção vai até o fim da caixinha', () {
    const me = Person(id: 'me', name: 'Você');
    Caixinha build({DateTime? end}) => Caixinha(
          id: 'proj',
          name: 'Proj',
          emoji: '🐷',
          monthlyQuota: 0,
          createdAt: DateTime(2026, 1, 1),
          endDate: end,
          members: const [CaixinhaMember(person: me, role: CaixinhaRole.owner)],
          contributions: [Contribution(id: 'c', personId: 'me', amount: 1000, date: DateTime(2026, 1, 5))],
          earnings: [Earning(id: 'e', amount: 100, source: EarningSource.investment, date: DateTime(2026, 2, 3))],
        );

    test('com data-limite, projeta exatamente até o mês do fim', () {
      final c = build(end: DateTime(2026, 6, 30));
      final s = c.monthlySeries(now: DateTime(2026, 2, 15));
      final proj = s.where((p) => p.projected).toList();
      expect(proj.length, 4); // mar, abr, mai, jun
      expect(proj.last.month, DateTime(2026, 6));
    });

    test('sem data-limite, projeta o horizonte padrão', () {
      final c = build();
      final s = c.monthlySeries(now: DateTime(2026, 2, 15), projectMonths: 12);
      expect(s.where((p) => p.projected).length, 12);
    });
  });

  group('Histórico — quem lançou (autoria)', () {
    const anaP = Person(id: 'ana', name: 'Ana', lastName: 'Prado');
    const brunoL = Person(id: 'bruno', name: 'Bruno', lastName: 'Lima');
    final c = Caixinha(
      id: 'aut',
      name: 'Aut',
      emoji: '🐷',
      createdAt: DateTime(2026, 1, 1),
      members: const [
        CaixinhaMember(person: anaP, role: CaixinhaRole.owner),
        CaixinhaMember(person: brunoL, role: CaixinhaRole.member),
      ],
      contributions: [
        // Ana (tesoureira) lançou o aporte do Bruno.
        Contribution(id: 'x', personId: 'bruno', amount: 100, date: DateTime(2026, 1, 5), recordedBy: 'ana'),
        // Aporte lançado pela própria pessoa: não mostra autoria.
        Contribution(id: 'y', personId: 'ana', amount: 100, date: DateTime(2026, 1, 6), recordedBy: 'ana'),
      ],
    );

    test('label usa nome completo; autoria só quando difere da pessoa-alvo', () {
      final mv = c.movements;
      final doBruno = mv.firstWhere((m) => m.label.contains('Bruno'));
      expect(doBruno.label, 'Aporte · Bruno Lima');
      expect(doBruno.recordedByName, 'Ana Prado');
      final daAna = mv.firstWhere((m) => m.label.contains('Ana'));
      expect(daAna.recordedByName, isNull);
    });
  });
}
