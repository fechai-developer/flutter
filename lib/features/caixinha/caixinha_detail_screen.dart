import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/icons.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/masks.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/member_name.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/sheet_handle.dart';
import '../../core/widgets/wave_card.dart';
import '../../data/models/caixinha.dart';
import '../../data/models/person.dart';
import '../../data/repositories/providers.dart';
import '../../theme/app_theme.dart';
import 'caixinha_report.dart';
import 'edit_caixinha_sheet.dart';

class CaixinhaDetailScreen extends ConsumerStatefulWidget {
  final String caixinhaId;
  /// Abre já com o guia de preenchimento (caixinha criada "já em andamento").
  final bool showGuide;
  const CaixinhaDetailScreen({super.key, required this.caixinhaId, this.showGuide = false});

  @override
  ConsumerState<CaixinhaDetailScreen> createState() => _CaixinhaDetailScreenState();
}

class _CaixinhaDetailScreenState extends ConsumerState<CaixinhaDetailScreen> {
  // Guia de preenchimento: abre só na PRIMEIRA vez (logo após criar a caixinha
  // "já em andamento"). Depois só reabre pelo menu "Preencher histórico" —
  // assim não fica aparecendo a cada visita.
  late bool _showGuide = widget.showGuide;

  static const _padding = EdgeInsets.fromLTRB(20, 12, 20, 96);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(caixinhaByIdProvider(widget.caixinhaId));

    return async.when(
      skipLoadingOnReload: true, // não pisca ao rebuscar por evento de realtime
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Erro: $e'))),
      // Tomador externo: visão restrita (só o próprio empréstimo + histórico).
      data: (c) => (c.memberById('me')?.isBorrower ?? false) ? _BorrowerScreen(c: c) : _scaffold(c),
    );
  }

  Widget _scaffold(Caixinha c) {
    // Badge da aba Quitação: quantas pessoas estão devendo (cota e/ou juros).
    final atrasados = c.contributingMembers
        .where((m) => !m.inviteDeclined && c.cotaArrearsOf(m.person.id).isLate)
        .length;
    final podeLancar = c.iAmTreasurer && c.isOpen;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: Icon(AppIcons.arrowLeft), onPressed: () => context.go('/caixinhas')),
          title: Row(
            children: [
              Text(c.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
          actions: [
            if (c.isOwner && c.isOpen)
              IconButton(
                icon: Icon(AppIcons.pencilSimple),
                tooltip: 'Editar caixinha',
                onPressed: () => showEditCaixinhaSheet(context, c),
              ),
            if (c.isOwner)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'guide') setState(() => _showGuide = true);
                  if (v == 'close') _confirmClose(context, ref, c);
                  if (v == 'delete') _confirmDelete(context, ref, c);
                },
                itemBuilder: (_) => [
                  if (c.isOpen) const PopupMenuItem(value: 'guide', child: Text('Preencher histórico')),
                  if (c.isOpen) const PopupMenuItem(value: 'close', child: Text('Encerrar e partilhar')),
                  // Só dá pra excluir de verdade uma caixinha vazia (criada por
                  // engano) — com lançamento, o caminho é encerrar (preserva o
                  // histórico de todo mundo).
                  if (!c.hasMovements) const PopupMenuItem(value: 'delete', child: Text('Excluir caixinha')),
                ],
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Início'),
              Tab(child: _TabLabel(text: 'Quitação', badge: atrasados)),
              Tab(child: _TabLabel(text: 'Empréstimos', badge: c.openLoans.length, subtle: true)),
              const Tab(text: 'Histórico'),
            ],
          ),
        ),
        // Lançamentos ficam num único botão flutuante — só dono/tesoureiro.
        floatingActionButton: podeLancar ? _LancarFab(onSelected: (a) => _lancar(a, c)) : null,
        body: TabBarView(
          children: [
            _tabInicio(c),
            _tabQuitacao(c),
            _tabEmprestimos(c),
            _tabHistorico(c),
          ],
        ),
      ),
    );
  }

  void _lancar(_AcaoLancamento a, Caixinha c) {
    switch (a) {
      case _AcaoLancamento.aporte:
        _lancarAporte(context, ref, c);
      case _AcaoLancamento.rendimento:
        _lancarRendimento(context, ref, c);
      case _AcaoLancamento.emprestimo:
        _novoEmprestimo(context, ref, c);
    }
  }

  // ---------- Aba 1: Início (posição, evolução, relatórios) ----------
  Widget _tabInicio(Caixinha c) => ListView(
        padding: _padding,
        children: [
          // Guia de preenchimento (só na 1ª visita de uma caixinha migrada).
          if (_showGuide && c.iAmTreasurer && c.isOpen)
            _OnboardingGuide(
              onCotas: () => _revisarCotas(context, c),
              onRendimento: () => _lancarRendimento(context, ref, c),
              onEmprestimo: () => _novoEmprestimo(context, ref, c),
              onDismiss: () => setState(() => _showGuide = false),
            ),
          WaveCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.isClosed ? 'Patrimônio final' : 'Patrimônio da caixinha',
                    style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Text(Money.format(c.patrimony), style: AppTheme.moneyStyle(fontSize: 36, color: Colors.white)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _WaveChip(
                      icon: AppIconsFill.usersThree,
                      label: '${c.memberCount} membros',
                      onTap: () => _membersSheet(context, ref, c),
                    ),
                    _WaveChip(icon: AppIcons.percent, label: 'juros ${_pct(c.defaultInterestPct)}'),
                    if (c.paymentDay != null)
                      _WaveChip(icon: AppIconsFill.calendarBlank, label: 'todo dia ${c.paymentDay}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _MyShareCard(c: c),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Stat(label: 'Em caixa', value: c.cashOnHand, icon: AppIconsFill.coins)),
              const SizedBox(width: 10),
              Expanded(
                child: _Stat(
                  label: 'Emprestado (${c.openLoans.length})',
                  value: c.outstandingReceivables,
                  icon: AppIcons.handshake,
                  valueCaption: c.outstandingLoanInterest > 0.005 ? '(${Money.format(c.outstandingLoanInterest)} juros)' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _Stat(label: 'Rendeu', value: c.totalEarnings, icon: AppIcons.trendingUp, positive: true)),
            ],
          ),
          const SizedBox(height: 20),
          _EvolutionCard(c: c),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _verProjecao(context, c),
                  icon: Icon(AppIcons.trendingUp, size: 18),
                  label: const Text('Projeção'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _opcoesRelatorio(context, c),
                  icon: Icon(AppIcons.pdf, size: 18),
                  label: const Text('Relatório'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (c.isClosed) ...[
            _ClosedBanner(c: c),
            _SectionTitle(title: 'Partilha', trailing: '${c.memberCount}'),
            const SizedBox(height: 8),
            for (final m in _orderedMembers(c)) _MemberRow(c: c, member: m),
            if (c.exitedMembers.isNotEmpty)
              for (final m in c.exitedMembers) _ExitedRow(c: c, member: m),
          ],
        ],
      );

  // ---------- Aba 2: Quitação (cotas mês a mês + atrasos com juros) ----------
  Widget _tabQuitacao(Caixinha c) => ListView(
        padding: _padding,
        children: [
          if (c.monthlyQuota <= 0)
            _EmptyLine(text: 'Esta caixinha não tem valor de cota definido. Edite a caixinha para acompanhar as cotas.')
          else ...[
            _CotasSection(c: c, ref: ref),
            const SizedBox(height: 24),
          ],
        ],
      );

  // ---------- Aba 3: Empréstimos ----------
  Widget _tabEmprestimos(Caixinha c) => ListView(
        padding: _padding,
        children: [
          _SectionTitle(title: 'Valores emprestados', trailing: c.openLoans.isEmpty ? null : '${c.openLoans.length} em aberto'),
          const SizedBox(height: 8),
          if (c.loans.isNotEmpty || (c.iAmTreasurer && c.isOpen)) const _OrganizerDisclaimer(),
          if (c.loans.isEmpty)
            _EmptyLine(text: 'Nada registrado aqui. Use pra anotar valores combinados entre pessoas de confiança.'),
          for (final l in c.loans) _LoanRow(c: c, loan: l, ref: ref),
        ],
      );

  // ---------- Aba 4: Histórico (extrato detalhado) ----------
  Widget _tabHistorico(Caixinha c) {
    final all = c.movements.reversed.toList(); // mais novo primeiro
    // Desfazer é do DONO e só com a caixinha aberta: aporte, rendimento, ajuste
    // e saída não têm tela de edição — quando saem errados, o caminho é apagar
    // e lançar de novo.
    final podeDesfazer = c.isOwner && c.isOpen;
    return ListView.builder(
      padding: _padding,
      itemCount: all.isEmpty ? 1 : all.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(title: 'Histórico', trailing: all.isEmpty ? null : '${all.length} lançamentos'),
                const SizedBox(height: 4),
                Text('Tudo que mexeu no patrimônio: quem lançou, para quem, valor e o saldo antes → depois.',
                    style: Theme.of(context).textTheme.bodySmall),
                if (all.isEmpty) ...[
                  const SizedBox(height: 12),
                  _EmptyLine(text: 'Nenhum lançamento ainda.'),
                ],
              ],
            ),
          );
        }
        final m = all[i - 1];
        return _MovementCard(
          movement: m,
          onUndo: podeDesfazer ? () => _desfazerMovimento(c, m) : null,
        );
      },
    );
  }

  /// Desfaz um lançamento do histórico (só o dono). Pede confirmação porque não
  /// há como reverter: o certo é apagar e lançar de novo com os dados corretos.
  Future<void> _desfazerMovimento(Caixinha c, CaixinhaMovement m) async {
    final detalhe = switch (m.kind) {
      MovementKind.contribution => 'O aporte sai do histórico e a posição de quem aportou volta ao que era.',
      MovementKind.earning => 'O rendimento sai do histórico e o patrimônio da caixinha volta ao que era.',
      MovementKind.adjustment => 'O ajuste manual sai do histórico e o saldo volta ao que era antes dele.',
      MovementKind.exit => 'A saída é cancelada: a pessoa volta a participar da caixinha, com a posição que tinha.',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desfazer este lançamento?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${m.label} · ${Money.format(m.amount.abs())}',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(detalhe, style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.coralAceso),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desfazer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(repositoryControllerProvider).undoMovement(c.id, kind: m.kind, sourceId: m.sourceId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lançamento desfeito'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  // ---------- Ações (bottom sheets) ----------

  Future<void> _lancarAporte(BuildContext context, WidgetRef ref, Caixinha c) async {
    // Inclui convidados ainda pendentes (grupo de confiança / migração): o
    // tesoureiro lança o aporte de quem adicionou, mesmo sem aceite ainda.
    final elegiveis = c.contributingMembers.where((m) => !m.inviteDeclined).toList();
    final now = DateTime.now();
    String personId = 'me';
    DateTime date = DateTime.now();
    CotaArrears arrearsOf(String pid) => c.paymentDay == null ? CotaArrears.none : c.cotaArrearsOf(pid, now: now);
    final amountCtrl = TextEditingController(
        text: c.suggestedAporteFor('me') > 0 ? Money.plain(c.suggestedAporteFor('me')) : '');
    void suggest() {
      final v = c.suggestedAporteFor(personId);
      amountCtrl.text = v > 0 ? Money.plain(v) : '';
    }
    final ok = await _sheet<bool>(context, 'Lançar aporte', (ctx, setSheet) {
      final theme = Theme.of(ctx);
      final arrears = arrearsOf(personId);
      final name = personId == 'me' ? 'Você' : (c.memberById(personId)?.person.fullName ?? '');
      return [
        Text('De quem é o aporte?', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in elegiveis)
              ChoiceChip(
                label: Text(m.person.id == 'me' ? 'Você' : m.person.name),
                selected: personId == m.person.id,
                onSelected: (_) => setSheet(() {
                  personId = m.person.id;
                  suggest();
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: amountCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Valor do aporte', prefixText: r'R$ '),
        ),
        // Aviso: aporte comum entra na competência da data; cobrança de juros do
        // atraso é na seção Quitações (fluxo próprio, justo, por meses inteiros).
        if (arrears.isLate) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.coralAceso.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.warningCircle, size: 16, color: AppColors.coralAceso),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$name está em atraso (${Money.format(arrears.total)}). Este aporte entra na '
                    'competência da data escolhida. Para cobrar os juros do atraso, use "Quitações em atraso".',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _DateRow(value: date, floor: DateTime(2020), onChanged: (d) => setSheet(() => date = d)),
      ];
    }, confirmLabel: 'Lançar', controllers: [amountCtrl]);
    if (ok == true) {
      final amount = Money.parse(amountCtrl.text) ?? 0;
      if (amount > 0) {
        await ref.read(repositoryControllerProvider).addContribution(c.id, personId: personId, amount: amount, date: date);
      }
    }
  }

  Future<void> _lancarRendimento(BuildContext context, WidgetRef ref, Caixinha c) async {
    DateTime date = DateTime.now();
    bool perda = false; // false = rendeu (positivo); true = perdeu (negativo)
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await _sheet<bool>(context, 'Resultado do mês', (ctx, setSheet) => [
          Text('Resultado do dinheiro parado (banco/poupança) no mês. Juros de '
              'empréstimo são lançados no próprio empréstimo.', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Rendeu')),
              ButtonSegment(value: true, label: Text('Perdeu')),
            ],
            selected: {perda},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setSheet(() => perda = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: perda ? 'Valor perdido no mês' : 'Valor rendido no mês',
              prefixText: r'R$ ',
              helperText: perda ? 'Baixa o saldo de todos proporcional à participação.' : null,
            ),
          ),
          const SizedBox(height: 12),
          _DateRow(value: date, floor: c.createdAt, onChanged: (d) => setSheet(() => date = d)),
          const SizedBox(height: 12),
          TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Observação (opcional)')),
        ], confirmLabel: 'Lançar', controllers: [amountCtrl, noteCtrl]);
    if (ok == true) {
      final v = Money.parse(amountCtrl.text) ?? 0;
      if (v > 0) {
        final note = noteCtrl.text.trim().isNotEmpty
            ? noteCtrl.text.trim()
            : (perda ? 'Prejuízo do mês' : 'Rendimento do investimento');
        await ref.read(repositoryControllerProvider).addEarning(
              c.id,
              amount: perda ? -v : v,
              source: EarningSource.investment,
              note: note,
              date: date,
            );
      }
    }
  }

  Future<void> _novoEmprestimo(BuildContext context, WidgetRef ref, Caixinha c) async {
    // Candidatos "pra dentro": membros contribuintes (menos você). Tomadores
    // externos já cadastrados podem ser reaproveitados.
    // Inclui membros que ainda não aceitaram — o empréstimo pode ser registrado
    // antes de o convite ser aceito (ex.: combinou presencialmente).
    final members = c.contributingMembers.where((m) => m.person.id != 'me' && !m.inviteDeclined).toList();
    final existingBorrowers = c.borrowers;
    const novo = '__novo__';
    String sel = novo; // por padrão, cadastrar novo de fora
    DateTime date = DateTime.now();
    final nameCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final principalCtrl = TextEditingController();
    final interestCtrl = TextEditingController(text: _pctPlain(c.defaultInterestPct));

    final ok = await _sheet<bool>(context, 'Registrar valor emprestado', (ctx, setSheet) => [
          Text('Pra quem foi o dinheiro?', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('+ Novo de fora'),
                selected: sel == novo,
                onSelected: (_) => setSheet(() => sel = novo),
              ),
              for (final m in existingBorrowers)
                ChoiceChip(
                  label: Text('${m.person.fullName} (de fora)'),
                  selected: sel == m.person.id,
                  onSelected: (_) => setSheet(() => sel = m.person.id),
                ),
              for (final m in members)
                ChoiceChip(
                  label: Text(m.person.fullName),
                  selected: sel == m.person.id,
                  onSelected: (_) => setSheet(() => sel = m.person.id),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Cadastro do tomador externo (igual a grupo/assinatura): nome +
          // sobrenome + telefone. Cria o perfil da pessoa; sem aceite.
          if (sel == novo) ...[
            Row(
              children: [
                Expanded(child: TextField(controller: nameCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nome'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: lastCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Sobrenome'))),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [BrPhoneInputFormatter()],
              decoration: const InputDecoration(labelText: 'Celular', hintText: '(11) 9...'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: principalCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setSheet(() {}),
            decoration: const InputDecoration(labelText: 'Valor emprestado', prefixText: r'R$ '),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: interestCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setSheet(() {}),
            decoration: const InputDecoration(labelText: 'Juros ao mês', suffixText: '%'),
          ),
          const SizedBox(height: 12),
          // Empréstimo pode ser bem antigo (ex.: migração do caderno) — deixa
          // datar livremente no passado. Não mexe em cotas/atrasos (que só olham
          // aportes por competência); só gera os juros retroativos mês a mês.
          _DateRow(value: date, floor: DateTime(2020), onChanged: (d) => setSheet(() => date = d)),
          // Prévia dos juros retroativos: ao datar o empréstimo no passado, um
          // lançamento cheio (taxa × valor) por mês decorrido já entra como
          // rendimento e é distribuído entre os participantes por competência.
          Builder(builder: (ctx) {
            final p = Money.parse(principalCtrl.text) ?? 0;
            final r = double.tryParse(interestCtrl.text.replaceAll(',', '.')) ?? c.defaultInterestPct;
            final retro = retroactiveLoanInterest(loanDate: date, principal: p, interestPct: r, now: DateTime.now());
            if (retro.isEmpty) return const SizedBox.shrink();
            final each = retro.first.amount;
            final total = retro.fold(0.0, (a, e) => a + e.amount);
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.mentaViva.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(AppIcons.trendingUp, size: 16, color: AppColors.verdeAguaProfundo),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Empréstimo no passado: já entram ${retro.length} ${retro.length == 1 ? 'mês' : 'meses'} '
                        'de juros (${retro.length} × ${Money.format(each)} = ${Money.format(total)}), '
                        'distribuídos entre os participantes.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ], confirmLabel: 'Registrar empréstimo', controllers: [nameCtrl, lastCtrl, phoneCtrl, principalCtrl, interestCtrl]);

    if (ok == true) {
      final principal = Money.parse(principalCtrl.text) ?? 0;
      final interest = double.tryParse(interestCtrl.text.replaceAll(',', '.')) ?? c.defaultInterestPct;
      Person? borrower;
      bool external;
      if (sel == novo) {
        final n = nameCtrl.text.trim();
        if (n.isNotEmpty && !isReservedName(n)) {
          final last = lastCtrl.text.trim();
          borrower = Person(id: const Uuid().v4(), name: n, lastName: last.isEmpty ? null : last, phone: digitsOf(phoneCtrl.text));
          external = true;
        } else {
          external = true;
        }
      } else {
        final m = c.memberById(sel);
        borrower = m?.person;
        external = m?.isBorrower ?? false;
      }
      if (principal > 0 && borrower != null) {
        await ref.read(repositoryControllerProvider).addLoan(
              c.id,
              borrower: borrower,
              external: external,
              principal: principal,
              interestPct: interest,
              date: date,
            );
      }
    }
  }

  /// Revisão de cotas mês a mês num sheet (parte do guia de preenchimento).
  /// Reaproveita a mesma seção de Cotas da tela, observando a caixinha para
  /// refletir cada confirmação sem fechar o sheet.
  Future<void> _revisarCotas(BuildContext context, Caixinha caixinha) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Consumer(
        builder: (ctx, ref2, _) {
          final c = ref2.watch(caixinhaByIdProvider(caixinha.id)).valueOrNull ?? caixinha;
          final theme = Theme.of(ctx);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Material(
              color: theme.scaffoldBackgroundColor,
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Revisar cotas', style: theme.textTheme.titleLarge)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Fechar',
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: Icon(AppIcons.close),
                          ),
                        ],
                      ),
                      Text('Navegue pelos meses e confirme quem já pagou a cota em cada um. '
                          'Se já informou o saldo de hoje na criação, não precisa refazer os aportes.',
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 12),
                      if (c.monthlyQuota > 0)
                        _CotasSection(c: c, ref: ref2)
                      else
                        Text('Defina o valor da cota (editar caixinha) para revisar as cotas.',
                            style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _adicionarMembro(BuildContext context, WidgetRef ref, Caixinha c) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ok = await _sheet<bool>(context, 'Novo participante', (ctx, setSheet) => [
          TextField(controller: nameCtrl, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nome')),
          const SizedBox(height: 12),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [BrPhoneInputFormatter()],
            decoration: const InputDecoration(labelText: 'Celular', hintText: '(11) 99999-8888'),
          ),
        ], confirmLabel: 'Adicionar', controllers: [nameCtrl, phoneCtrl]);
    if (ok == true) {
      final n = nameCtrl.text.trim();
      if (n.isNotEmpty && !isReservedName(n)) {
        await ref.read(repositoryControllerProvider).addCaixinhaMember(
              c.id,
              Person(id: const Uuid().v4(), name: n, phone: digitsOf(phoneCtrl.text)),
            );
      }
    }
  }

  /// Janela dos membros (ponto 5): sai da tela principal e sobe ao tocar no
  /// contador de membros. Observa a caixinha para refletir edições feitas por
  /// dentro dela (adicionar, cotas, tesoureiro, saída) sem fechar o sheet.
  Future<void> _membersSheet(BuildContext context, WidgetRef ref, Caixinha caixinha) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Consumer(
        builder: (ctx, ref2, _) {
          final c = ref2.watch(caixinhaByIdProvider(caixinha.id)).valueOrNull ?? caixinha;
          final theme = Theme.of(ctx);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Material(
              color: theme.scaffoldBackgroundColor,
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SheetHandle(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text('Membros', style: theme.textTheme.titleLarge),
                          const Spacer(),
                          Text('${c.memberCount}', style: theme.textTheme.bodySmall),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final m in _orderedMembers(c))
                        _MemberRow(
                          c: c,
                          member: m,
                          onTap: (c.iAmTreasurer && c.isOpen && !m.isOwner) ? () => _memberSheet(ctx, ref2, c, m) : null,
                        ),
                      if (c.iAmTreasurer && c.isOpen)
                        TextButton.icon(
                          onPressed: () => _adicionarMembro(ctx, ref2, c),
                          icon: Icon(AppIcons.plus, size: 18),
                          label: const Text('Adicionar participante'),
                        ),
                      if (c.exitedMembers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final m in c.exitedMembers) _ExitedRow(c: c, member: m),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _memberSheet(BuildContext context, WidgetRef ref, Caixinha c, CaixinhaMember member) async {
    final ctrl = ref.read(repositoryControllerProvider);
    final pid = member.person.id;
    // Nome + sobrenome: daqui saem confirmações de saída e de papel, que viram
    // registro no histórico — não pode ficar ambíguo entre dois homônimos.
    final name = pid == 'me' ? 'Você' : member.person.fullName;
    var quotas = member.quotas;
    var isTreasurer = member.role == CaixinhaRole.treasurer;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          final refund = c.refundBaseOf(pid);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Material(
              color: theme.scaffoldBackgroundColor,
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      MemberAvatar(name: member.person.name, lastName: pid == 'me' ? null : member.person.lastName, size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: theme.textTheme.titleLarge),
                            Text('${(c.participationOf(pid) * 100).toStringAsFixed(1)}% · aportou ${Money.format(refund)}',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      MoneyText(c.balanceOf(pid), fontSize: 16),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Cotas
                  Row(
                    children: [
                      Text('Cotas', style: theme.textTheme.titleMedium),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          c.hasMovements ? 'travado — já tem lançamento nessa caixinha' : 'cada cota = ${Money.format(c.monthlyQuota)}/mês',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      IconButton.outlined(
                        onPressed: (!c.hasMovements && quotas > 1)
                            ? () {
                                setSheet(() => quotas--);
                                ctrl.setMemberQuotas(c.id, pid, quotas);
                              }
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(width: 36, child: Text('$quotas', textAlign: TextAlign.center, style: theme.textTheme.titleLarge)),
                      IconButton.outlined(
                        onPressed: c.hasMovements
                            ? null
                            : () {
                                setSheet(() => quotas++);
                                ctrl.setMemberQuotas(c.id, pid, quotas);
                              },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  // Tesoureiro (não se aplica ao dono)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tesoureiro'),
                    subtitle: const Text('Pode lançar aportes, rendimentos e empréstimos'),
                    value: isTreasurer,
                    activeColor: AppColors.verdeAguaProfundo,
                    onChanged: (v) {
                      setSheet(() => isTreasurer = v);
                      ctrl.setTreasurer(c.id, pid, v);
                    },
                  ),
                  // Ajuste manual de saldo — só o dono.
                  if (c.isOwner) ...[
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Ajustar saldo', style: theme.textTheme.titleMedium),
                              Text('Corrige o saldo desta pessoa (entra no histórico como ajuste)',
                                  style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _ajustarSaldo(context, ref, c, member);
                          },
                          child: const Text('Ajustar'),
                        ),
                      ],
                    ),
                  ],
                  const Divider(height: 24),
                  Text('Sair da caixinha', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '$name recebe de volta ${Money.format(refund)} — só o que aportou, sem rendimento. '
                    'O lucro que sobra fica para quem continua.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.coralAceso,
                        side: const BorderSide(color: AppColors.coralAceso),
                      ),
                      icon: Icon(AppIcons.trash, size: 18),
                      label: Text('Remover e devolver ${Money.format(refund)}'),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: ctx,
                          builder: (d) => AlertDialog(
                            title: Text('Remover $name?'),
                            content: Text('$name sai da caixinha e recebe ${Money.format(refund)} de volta '
                                '(sem rendimento). Isso fica registrado no histórico.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
                              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remover')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await ctrl.exitMember(c.id, pid, refund: refund);
                          if (ctx.mounted) Navigator.pop(ctx);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _ajustarSaldo(BuildContext context, WidgetRef ref, Caixinha c, CaixinhaMember member) async {
    final pid = member.person.id;
    final name = pid == 'me' ? 'Você' : member.person.fullName;
    final current = c.balanceOf(pid);
    final ctrl = TextEditingController(text: Money.plain(current));
    final ok = await _sheet<bool>(context, 'Ajustar saldo · $name', (ctx, setSheet) {
      final novo = Money.parse(ctrl.text) ?? current;
      final delta = novo - current;
      final theme = Theme.of(ctx);
      return [
        Text('Saldo atual de $name: ${Money.format(current)}. Informe o novo saldo — a '
            'diferença entra no histórico como "Ajuste manual" e muda o patrimônio.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setSheet(() {}),
          decoration: const InputDecoration(labelText: 'Novo saldo', prefixText: r'R$ '),
        ),
        const SizedBox(height: 8),
        Text(
          delta.abs() < 0.005
              ? 'Sem diferença.'
              : 'Diferença: ${delta > 0 ? '+' : '−'} ${Money.format(delta.abs())}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: delta >= 0 ? AppColors.verdeAguaProfundo : AppColors.coralAceso,
            fontWeight: FontWeight.w600,
          ),
        ),
      ];
    }, confirmLabel: 'Aplicar ajuste', controllers: [ctrl]);
    if (ok == true) {
      final novo = Money.parse(ctrl.text) ?? current;
      final delta = double.parse((novo - current).toStringAsFixed(2));
      if (delta.abs() > 0.005) {
        await ref.read(repositoryControllerProvider).adjustBalance(c.id, pid, delta: delta, note: 'Ajuste de saldo');
      }
    }
  }

  Future<void> _opcoesRelatorio(BuildContext context, Caixinha c) async {
    var incluirHistorico = true;
    final ok = await _sheet<bool>(context, 'Gerar relatório (PDF)', (ctx, setSheet) => [
          Text('Extrato com resumo, partilha por participante e valores emprestados.',
              style: Theme.of(ctx).textTheme.bodySmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Incluir histórico'),
            subtitle: const Text('Todas as movimentações, do início ao atual'),
            value: incluirHistorico,
            activeColor: AppColors.verdeAguaProfundo,
            onChanged: (v) => setSheet(() => incluirHistorico = v),
          ),
        ], confirmLabel: 'Gerar PDF');
    if (ok == true) {
      await shareCaixinhaReport(c, includeHistory: incluirHistorico);
    }
  }

  Future<void> _verProjecao(BuildContext context, Caixinha c) async {
    final monthsCtrl = TextEditingController(text: '${c.periodMonths ?? 12}');
    final rateCtrl = TextEditingController(text: '0,5');

    ProjectionResult compute() {
      final months = int.tryParse(monthsCtrl.text) ?? 12;
      final rate = double.tryParse(rateCtrl.text.replaceAll(',', '.')) ?? 0;
      return c.project(months: months, monthlyRatePct: rate);
    }

    final gerar = await _sheet<bool>(context, 'Projeção — se todos pagarem em dia', (ctx, setSheet) {
      final p = compute();
      final theme = Theme.of(ctx);
      return [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: monthsCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setSheet(() {}),
                decoration: const InputDecoration(labelText: 'Período (meses)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setSheet(() {}),
                decoration: const InputDecoration(labelText: 'Juros médio/mês', suffixText: '%'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Destaque do total projetado (pra print).
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: WaveCard.balanceGradient,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Em ${p.months} meses, vocês terão juntos',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(Money.format(p.totalProjected), style: AppTheme.moneyStyle(fontSize: 32, color: Colors.white)),
              const SizedBox(height: 4),
              Text(
                  p.totalYield >= 0
                      ? '${Money.format(p.totalContributed)} aportado · + ${Money.format(p.totalYield)} de rendimento'
                      : '${Money.format(p.totalContributed)} aportado · ${Money.format(p.totalYield.abs())} de prejuízo a recuperar',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Por pessoa', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        for (final pp in p.people)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                MemberAvatar(name: pp.name, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pp.name, style: theme.textTheme.titleMedium),
                      Text('colocou ${Money.format(pp.contributed)} · + ${Money.format(pp.profit)}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                MoneyText(pp.projected, fontSize: 16),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text('Estimativa (todos em dia, rendimento médio). Não considera empréstimos. Não é garantia.',
            style: theme.textTheme.bodySmall),
      ];
    }, confirmLabel: 'Gerar relatório (PDF)', controllers: [monthsCtrl, rateCtrl]);

    if (gerar == true) {
      await shareCaixinhaReport(c, projection: compute(), includeHistory: true);
    }
  }

  Future<void> _confirmClose(BuildContext context, WidgetRef ref, Caixinha c) async {
    final theme = Theme.of(context);
    final openLoans = c.openLoans;
    final lateMembers = c.contributingMembers
        .where((m) => !m.inviteDeclined && c.cotaArrearsOf(m.person.id).isLate)
        .toList();

    // Bloqueia encerramento enquanto houver pendências — cotas em atraso ou
    // empréstimos em aberto. Ambos afetam o balanceOf e precisam ser resolvidos
    // (quitados, registrados ou baixados como perda) para a partilha fechar certo.
    if (openLoans.isNotEmpty || lateMembers.isNotEmpty) {
      final tabController = DefaultTabController.of(context);

      Widget blockRow(String label, String value) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                Text(value, style: AppTheme.moneyStyle(fontSize: 14)),
              ],
            ),
          );

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pendências em aberto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resolva os itens abaixo antes de encerrar e partilhar.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (lateMembers.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Cotas em atraso', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  for (final m in lateMembers)
                    blockRow(
                      m.person.id == 'me' ? 'Você' : m.person.fullName,
                      Money.format(c.cotaArrearsOf(m.person.id).total),
                    ),
                ],
                if (openLoans.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Empréstimos em aberto', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  for (final l in openLoans)
                    blockRow(l.borrowerName, Money.format(c.outstandingOf(l))),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
            if (lateMembers.isNotEmpty)
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  tabController.animateTo(1); // aba Quitação
                },
                child: const Text('Ver cotas'),
              ),
            if (openLoans.isNotEmpty)
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  tabController.animateTo(2); // aba Empréstimos
                },
                child: const Text('Ver empréstimos'),
              ),
          ],
        ),
      );
      return;
    }

    // Sem pendências: confirma encerramento com partilha por pessoa.
    final members = _orderedMembers(c);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encerrar e partilhar?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('A caixinha para de receber aportes e vira somente-leitura. '
                  'Cada um leva, proporcional à participação:'),
              const SizedBox(height: 12),
              for (final m in members)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(m.person.id == 'me' ? 'Você' : m.person.fullName,
                            style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                      ),
                      Text(Money.format(c.balanceOf(m.person.id)),
                          style: AppTheme.moneyStyle(fontSize: 14)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Encerrar')),
        ],
      ),
    );
    if (ok == true) await ref.read(repositoryControllerProvider).closeCaixinha(c.id);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Caixinha c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir caixinha?'),
        content: const Text('Essa caixinha ainda não tem nenhum lançamento — a exclusão não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(repositoryControllerProvider).deleteCaixinha(c.id);
      if (context.mounted) context.go('/caixinhas');
    }
  }
}

/// Sheet genérico com título + campos + botão de confirmar. Retorna `true` no
/// pop. Os [controllers] passados são descartados no `dispose()` do próprio
/// sheet — **depois** da animação de saída —, evitando o "TextEditingController
/// used after being disposed" ao fechar com ESC.
Future<T?> _sheet<T>(
  BuildContext context,
  String title,
  List<Widget> Function(BuildContext ctx, void Function(void Function()) setSheet) fields, {
  required String confirmLabel,
  List<TextEditingController> controllers = const [],
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SheetBody<T>(
      title: title,
      fields: fields,
      confirmLabel: confirmLabel,
      controllers: controllers,
    ),
  );
}

class _SheetBody<T> extends StatefulWidget {
  final String title;
  final List<Widget> Function(BuildContext ctx, void Function(void Function()) setSheet) fields;
  final String confirmLabel;
  final List<TextEditingController> controllers;
  const _SheetBody({
    required this.title,
    required this.fields,
    required this.confirmLabel,
    required this.controllers,
  });

  @override
  State<_SheetBody<T>> createState() => _SheetBodyState<T>();
}

class _SheetBodyState<T> extends State<_SheetBody<T>> {
  @override
  void dispose() {
    for (final c in widget.controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge)),
                  // Botão de fechar explícito (além de arrastar/tocar fora) — some
                  // gente não descobre os gestos. Fecha sem confirmar (retorna null).
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(AppIcons.close),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            ...widget.fields(context, (fn) => setState(fn)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true as T),
                child: Text(widget.confirmLabel),
              ),
            ),
          ],
        ),
        ),
        ),
      ),
    );
  }
}

List<CaixinhaMember> _orderedMembers(Caixinha c) {
  // Só contribuintes entram na lista de membros; tomadores externos aparecem
  // na seção de empréstimos.
  final contributing = c.contributingMembers;
  final others = contributing.where((m) => m.person.id != 'me').toList()
    ..sort((a, b) => a.person.name.toLowerCase().compareTo(b.person.name.toLowerCase()));
  return [...contributing.where((m) => m.person.id == 'me'), ...others];
}

String _pct(double v) => '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)}%';
String _pctPlain(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

class _WaveChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _WaveChip({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(borderRadius: BorderRadius.circular(100), onTap: onTap, child: chip),
    );
  }
}

class _MyShareCard extends StatelessWidget {
  final Caixinha c;
  const _MyShareCard({required this.c});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = c.balanceOf('me');
    final pct = c.participationOf('me');
    final profit = c.profitOf('me');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sua parte', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              MoneyText(share, fontSize: 26),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${(pct * 100).toStringAsFixed(1)}% da caixinha', style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                profit >= 0 ? '+ ${Money.format(profit)} de lucro' : Money.format(profit),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: profit > 0 ? AppColors.verdeAguaProfundo : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final bool positive;

  /// Texto pequeno e discreto mostrado ao lado do valor (ex.: parte de juros
  /// embutida no valor emprestado).
  final String? valueCaption;

  const _Stat({required this.label, required this.value, required this.icon, this.positive = false, this.valueCaption});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: positive ? AppColors.verdeAguaProfundo : AppColors.textoSuave),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              MoneyText(value, fontSize: 15, color: positive && value > 0 ? AppColors.verdeAguaProfundo : null),
              if (valueCaption != null)
                Text(valueCaption!,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textoSuave, fontSize: 11)),
            ],
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Card com a evolução do patrimônio: linha COM rendimento (patrimônio) × SEM
/// rendimento (só aportes acumulados), mais projeção tracejada dos próximos
/// meses. Sem lib de chart no projeto → CustomPainter próprio.
class _EvolutionCard extends StatelessWidget {
  final Caixinha c;
  const _EvolutionCard({required this.c});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = c.monthlySeries();
    if (series.length < 2) return const SizedBox.shrink();
    final hasProjection = series.any((p) => p.projected);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Evolução', style: theme.textTheme.titleMedium),
              const Spacer(),
              MoneyText(c.patrimony, fontSize: 16),
            ],
          ),
          const SizedBox(height: 14),
          _EvolutionChart(series: series),
          const SizedBox(height: 10),
          Row(
            children: [
              const _LegendDot(color: AppColors.verdeAguaProfundo, label: 'Com rendimento'),
              const SizedBox(width: 14),
              const _LegendDot(color: AppColors.textoSuave, label: 'Só aportes'),
              const Spacer(),
              if (hasProjection)
                Text('- - projeção', style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.textoSuave)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
      ],
    );
  }
}

/// Envolve o gráfico com gestos: tocar/arrastar (mobile) ou passar o mouse
/// (web/desktop) fixa um mês e mostra um balão com o valor daquele mês. Tocar
/// no mesmo ponto de novo desfaz a seleção.
class _EvolutionChart extends StatefulWidget {
  final List<CaixinhaSeriesPoint> series;
  const _EvolutionChart({required this.series});

  @override
  State<_EvolutionChart> createState() => _EvolutionChartState();
}

class _EvolutionChartState extends State<_EvolutionChart> {
  int? _sel;

  int _indexAt(double dx, double w) {
    final n = widget.series.length;
    if (n < 2 || w <= 0) return 0;
    return (dx / w * (n - 1)).round().clamp(0, n - 1);
  }

  void _hover(double dx, double w) {
    final i = _indexAt(dx, w);
    if (i != _sel) setState(() => _sel = i);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      return MouseRegion(
        onHover: (e) => _hover(e.localPosition.dx, w),
        onExit: (_) => setState(() => _sel = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            final i = _indexAt(d.localPosition.dx, w);
            setState(() => _sel = _sel == i ? null : i);
          },
          onHorizontalDragStart: (d) => _hover(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _hover(d.localPosition.dx, w),
          child: SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(painter: _EvolutionPainter(widget.series, selected: _sel)),
          ),
        ),
      );
    });
  }
}

class _EvolutionPainter extends CustomPainter {
  final List<CaixinhaSeriesPoint> pts;
  final int? selected;
  _EvolutionPainter(this.pts, {this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    const topPad = 8.0;
    const bottomPad = 18.0; // faixa dos rótulos de mês
    final w = size.width;
    final h = size.height;
    final baseline = h - bottomPad;
    final n = pts.length;
    final realCount = pts.where((p) => !p.projected).length;

    var maxV = 0.0;
    for (final p in pts) {
      maxV = math.max(maxV, math.max(p.patrimony, p.contributed));
    }
    if (maxV <= 0) maxV = 1;

    double x(int i) => n == 1 ? w / 2 : w * i / (n - 1);
    double y(double v) => topPad + (baseline - topPad) * (1 - v / maxV);

    final patrO = [for (var i = 0; i < n; i++) Offset(x(i), y(pts[i].patrimony))];
    final contribO = [for (var i = 0; i < n; i++) Offset(x(i), y(pts[i].contributed))];
    final b = realCount - 1; // último índice real (fronteira com a projeção)

    // Área suave sob a linha de patrimônio.
    final areaPath = Path()..moveTo(patrO.first.dx, patrO.first.dy);
    for (final o in patrO.skip(1)) {
      areaPath.lineTo(o.dx, o.dy);
    }
    areaPath
      ..lineTo(patrO.last.dx, baseline)
      ..lineTo(patrO.first.dx, baseline)
      ..close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x2E17A78F), Color(0x0017A78F)],
        ).createShader(Rect.fromLTWH(0, topPad, w, baseline - topPad)),
    );

    final contribPaint = Paint()
      ..color = AppColors.textoSuave.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final patrPaint = Paint()
      ..color = AppColors.verdeAguaProfundo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Fronteira "hoje" (linha vertical discreta) quando há projeção.
    if (realCount < n && b >= 0) {
      final bx = x(b);
      final markPaint = Paint()
        ..color = AppColors.textoSuave.withValues(alpha: 0.35)
        ..strokeWidth = 1;
      _dash(canvas, Offset(bx, topPad), Offset(bx, baseline), markPaint, dash: 3, gap: 3);
    }

    // Real (sólido) e projeção (tracejado) começando na fronteira p/ conectar.
    _poly(canvas, contribO.sublist(0, realCount), contribPaint);
    _poly(canvas, patrO.sublist(0, realCount), patrPaint);
    if (realCount < n && b >= 0) {
      _poly(canvas, contribO.sublist(b), contribPaint, dashed: true);
      _poly(canvas, patrO.sublist(b), patrPaint, dashed: true);
    }

    // Pontinho em cada mês (real cheio, projeção vazado) — deixa a evolução
    // legível "mês a mês", inclusive na parte futura, sem parecer que salta.
    final dotFill = Paint()..color = AppColors.verdeAguaProfundo;
    final dotHollow = Paint()
      ..color = AppColors.verdeAguaProfundo.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var i = 0; i < n; i++) {
      if (i == b) continue; // a fronteira "hoje" ganha o marcador destacado abaixo
      final projected = i > b;
      canvas.drawCircle(patrO[i], projected ? 2.2 : 2.4, projected ? dotHollow : dotFill);
    }

    // Ponto de "hoje" no patrimônio.
    if (b >= 0) {
      canvas.drawCircle(patrO[b], 3.5, Paint()..color = AppColors.verdeAguaProfundo);
      canvas.drawCircle(patrO[b], 3.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }

    // Rótulos de mês distribuídos no eixo (início → fim, incluindo os meses
    // futuros da projeção). Passo adaptativo para caber sem sobrepor.
    final labelY = baseline + 3;
    final maxLabels = math.max(2, (w / 46).floor());
    final step = (n / maxLabels).ceil().clamp(1, n);
    final idxs = <int>{0, n - 1};
    for (var i = step; i < n - 1; i += step) {
      idxs.add(i);
    }
    // Evita rótulo colado no último (descarta o escolhido perto demais do fim).
    idxs.removeWhere((i) => i != 0 && i != n - 1 && (n - 1 - i) < (step / 2).ceil());
    final ordered = idxs.toList()..sort();
    for (final i in ordered) {
      final align = i == 0
          ? Alignment.centerLeft
          : i == n - 1
              ? Alignment.centerRight
              : Alignment.center;
      _label(canvas, _fmtMonth(pts[i].month), Offset(x(i), labelY), align);
    }

    // Mês selecionado (toque/hover): linha-guia vertical, ponto destacado e
    // balão com o valor daquele mês (patrimônio + aportado).
    final sel = selected;
    if (sel != null && sel >= 0 && sel < n) {
      final p = pts[sel];
      final sx = x(sel);
      final sy = y(p.patrimony);
      canvas.drawLine(
        Offset(sx, topPad),
        Offset(sx, baseline),
        Paint()
          ..color = AppColors.verdeAguaProfundo.withValues(alpha: 0.4)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(Offset(sx, sy), 4.5, Paint()..color = AppColors.verdeAguaProfundo);
      canvas.drawCircle(Offset(sx, sy), 4.5,
          Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
      _tooltip(canvas, sx, w, p);
    }
  }

  /// Balão fixo no topo do gráfico com o mês e os valores (patrimônio e
  /// aportado) do ponto selecionado. Centraliza no ponto, mas fica dentro da
  /// largura.
  void _tooltip(Canvas canvas, double sx, double w, CaixinhaSeriesPoint p) {
    final title = '${_fmtMonth(p.month)}${p.projected ? ' · projeção' : ''}';
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(children: [
        TextSpan(text: '$title\n', style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w600)),
        TextSpan(text: Money.format(p.patrimony), style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w700)),
        TextSpan(text: '\naportado ${Money.format(p.contributed)}', style: const TextStyle(fontSize: 10, color: Colors.white70)),
      ]),
    )..layout();
    const pad = 8.0;
    final boxW = tp.width + pad * 2;
    final boxH = tp.height + pad * 2;
    final left = (sx - boxW / 2).clamp(0.0, math.max(0.0, w - boxW)).toDouble();
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(left, 0, boxW, boxH), const Radius.circular(8));
    canvas.drawRRect(rect, Paint()..color = AppColors.verdeAguaProfundo);
    tp.paint(canvas, Offset(left + pad, pad));
  }

  static const _mesesAbbr = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  static String _fmtMonth(DateTime d) => '${_mesesAbbr[d.month - 1]}/${d.year % 100}';

  void _label(Canvas canvas, String text, Offset at, Alignment align) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 10, color: AppColors.textoSuave)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (align == Alignment.center) dx -= tp.width / 2;
    if (align == Alignment.centerRight) dx -= tp.width;
    tp.paint(canvas, Offset(math.max(0, dx), at.dy));
  }

  void _poly(Canvas canvas, List<Offset> o, Paint paint, {bool dashed = false}) {
    if (o.length < 2) return;
    if (!dashed) {
      final path = Path()..moveTo(o.first.dx, o.first.dy);
      for (final p in o.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    } else {
      for (var i = 0; i < o.length - 1; i++) {
        _dash(canvas, o[i], o[i + 1], paint);
      }
    }
  }

  void _dash(Canvas canvas, Offset a, Offset b, Paint paint, {double dash = 5, double gap = 4}) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final start = a + dir * d;
      final end = a + dir * math.min(d + dash, total);
      canvas.drawLine(start, end, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_EvolutionPainter oldDelegate) =>
      oldDelegate.pts != pts || oldDelegate.selected != selected;
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  const _SectionTitle({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const Spacer(),
        if (trailing != null) Text(trailing!, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final Caixinha c;
  final CaixinhaMember member;
  final VoidCallback? onTap;
  const _MemberRow({required this.c, required this.member, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = member.person.id == 'me';
    final pct = c.participationOf(member.person.id);
    final share = c.balanceOf(member.person.id);
    final contributed = c.contributedBy(member.person.id);
    final cotas = member.quotas > 1 ? '${member.quotas} cotas · ' : '';

    final content = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Row(
        children: [
          MemberAvatar(name: member.person.name, lastName: isMe ? null : member.person.lastName, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: MemberName(
                        isMe ? 'Você' : member.person.fullName,
                        status: member.inviteStatus,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                      ),
                    ),
                    if (member.isTreasurer) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.verdeAguaProfundo.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(member.isOwner ? 'dono' : 'tesoureiro',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.verdeAguaProfundo)),
                      ),
                    ],
                    if (!isMe) MemberStatusChip(member.inviteStatus),
                  ],
                ),
                const SizedBox(height: 2),
                Text('$cotas${(pct * 100).toStringAsFixed(1)}% · aportou ${Money.format(contributed)}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          MoneyText(share, fontSize: 15),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(AppIcons.caretRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              child: InkWell(borderRadius: BorderRadius.circular(AppTheme.cardRadius), onTap: onTap, child: content),
            ),
    );
  }
}

/// Cotas por mês: quem pagou / quanto falta. Navega do início da caixinha até
/// o mês atual, sinalizando os meses com pendência (só as próprias, se o
/// usuário não for tesoureiro/dono). O tesoureiro confirma o pagamento (lança o
/// aporte pendente no mês selecionado) direto daqui.
class _CotasSection extends StatefulWidget {
  final Caixinha c;
  final WidgetRef ref;
  const _CotasSection({required this.c, required this.ref});

  @override
  State<_CotasSection> createState() => _CotasSectionState();
}

class _CotasSectionState extends State<_CotasSection> {
  static const _meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

  final DateTime _now = DateTime.now();
  late DateTime _sel = DateTime(_now.year, _now.month);
  bool _arrearsOpen = false; // seção de quitação (tesoureiro) começa recolhida

  static int _ix(DateTime d) => d.year * 12 + d.month;
  static bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;
  static String _label(DateTime d) => '${_meses[d.month - 1]}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.c;
    final start = DateTime(c.periodStart.year, c.periodStart.month);
    final current = DateTime(_now.year, _now.month);
    // Até onde dá pra navegar pra frente: o fim da caixinha (quando há data-
    // limite futura) ou o mês atual. Permite ver e pré-quitar meses futuros.
    final endMonth = c.endDate != null ? DateTime(c.endDate!.year, c.endDate!.month) : current;
    final lastMonth = _ix(endMonth) > _ix(current) ? endMonth : current;
    // Mantém o mês selecionado dentro do intervalo válido em rebuilds.
    if (_ix(_sel) < _ix(start)) _sel = start;
    if (_ix(_sel) > _ix(lastMonth)) _sel = lastMonth;

    // Inclui convidados pendentes (o dono acompanha todo mundo que adicionou;
    // migração do caderno raramente tem aceite). Só exclui quem recusou.
    final ativos = c.contributingMembers.where((m) => !m.inviteDeclined).toList();
    final pendentes = ativos.where((m) => c.cotaPendingThisMonth(m.person.id, _sel) > 0.005).length;
    // Grupo de confiança: todos enxergam as pendências de todos (a edição
    // — confirmar/quitar — segue restrita a tesoureiro/dono).
    final pendingMonths = c.monthsWithPendencies(onlyMe: false, now: _now);
    final outros = pendingMonths.where((d) => !_same(d, _sel)).toList();

    final canPrev = _ix(_sel) > _ix(start);
    final canNext = _ix(_sel) < _ix(lastMonth);
    // Mês futuro: não é "pendência" (ainda não venceu) — é adiantamento de cota.
    final isFuture = _ix(_sel) > _ix(current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Cotas', style: theme.textTheme.titleLarge),
            const Spacer(),
            Text(
              isFuture ? 'mês futuro' : (pendentes == 0 ? 'tudo em dia' : '$pendentes pendente(s)'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Navegação de meses.
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: canPrev ? () => setState(() => _sel = DateTime(_sel.year, _sel.month - 1)) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_label(_sel), style: theme.textTheme.titleMedium),
                  if (pendentes > 0 && !isFuture) ...[
                    const SizedBox(width: 6),
                    Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.coralAceso, shape: BoxShape.circle)),
                  ],
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: canNext ? () => setState(() => _sel = DateTime(_sel.year, _sel.month + 1)) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        if (isFuture)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              c.iAmTreasurer && c.isOpen
                  ? 'Mês à frente — dá pra adiantar a cota de quem quiser.'
                  : 'Mês à frente — cota ainda não vencida.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textoSuave),
            ),
          ),
        for (final m in ativos)
          Builder(builder: (context) {
            final pid = m.person.id;
            final pending = c.cotaPendingThisMonth(pid, _sel);
            final paid = pending <= 0.005;
            final name = pid == 'me' ? 'Você' : m.person.fullName;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(paid ? AppIconsFill.checkCircle : AppIcons.clockCountdown,
                      size: 18, color: paid ? AppColors.verdeAguaProfundo : AppColors.textoSuave),
                  const SizedBox(width: 10),
                  Expanded(child: Text(name, style: theme.textTheme.bodyMedium)),
                  if (paid)
                    Text('pago', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.verdeAguaProfundo))
                  else ...[
                    Text(
                        isFuture
                            ? 'adiantar ${Money.format(pending)}'
                            : '${_overdue(c, _sel) ? 'atrasado' : 'falta'} ${Money.format(pending)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: _overdue(c, _sel) && !isFuture ? AppColors.coralAceso : null)),
                    // Registro do mês (editável: valor + data). Vale para mês
                    // vencido também — é lançamento de aporte, SEM juros. A
                    // quitação com juros fica no bloco "Em atraso" abaixo.
                    if (c.iAmTreasurer && c.isOpen) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _registrarCotaMes(context, c, m, _sel, pending),
                        borderRadius: BorderRadius.circular(100),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: AppColors.verdeAguaProfundo, borderRadius: BorderRadius.circular(100)),
                          child: Text(isFuture ? 'Adiantar' : 'Registrar',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            );
          }),
        // Quitação (com juros) — só tesoureiro/dono, em seção própria recolhível
        // com badge da quantidade. Aparece só quando há atraso e há dia de
        // vencimento definido. Membro comum vê o status por mês na lista acima.
        if (c.iAmTreasurer && c.isOpen && c.paymentDay != null)
          Builder(builder: (context) {
            final list = ativos
                .map((m) => (m: m, a: c.cotaArrearsOf(m.person.id, now: _now)))
                .where((e) => e.a.isLate)
                .toList();
            if (list.isEmpty) return const SizedBox.shrink();
            final totalDevido = list.fold(0.0, (a, e) => a + e.a.total);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 18),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _arrearsOpen = !_arrearsOpen),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(AppIcons.warningCircle, size: 18, color: AppColors.coralAceso),
                        const SizedBox(width: 8),
                        Text('Quitações em atraso', style: theme.textTheme.titleMedium),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.coralAceso, borderRadius: BorderRadius.circular(100)),
                          child: Text('${list.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                        const Spacer(),
                        MoneyText(totalDevido, fontSize: 14, color: AppColors.coralAceso),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _arrearsOpen ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(AppIcons.caretDown, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_arrearsOpen) ...[
                  const SizedBox(height: 4),
                  Text('Cota vencida rende ${_pct(c.defaultInterestPct)} ao mês, como um empréstimo — os juros viram rendimento da caixinha. '
                      'Para registrar um pagamento em dia do passado (sem juros), use "Registrar" no mês.',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 10),
                  for (final e in list)
                    _ArrearsRow(
                      name: e.m.person.id == 'me' ? 'Você' : e.m.person.fullName,
                      arrears: e.a,
                      onQuitar: () => _quitarAtraso(context, c, e.m),
                    ),
                ],
              ],
            );
          }),
        // Atalho para os outros meses com pendência.
        if (outros.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Meses com pendência:', style: theme.textTheme.bodySmall),
              for (final d in outros)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_label(d)),
                  avatar: Icon(AppIcons.clockCountdown, size: 14, color: AppColors.coralAceso),
                  onPressed: () => setState(() => _sel = d),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Um mês está "vencido" quando o dia de pagamento já passou (data de hoje
  /// depois do aniversário daquele mês). Sem dia de pagamento, nunca vence.
  bool _overdue(Caixinha c, DateTime month) {
    final day = c.paymentDay;
    if (day == null) return false;
    final dim = DateTime(month.year, month.month + 1, 0).day;
    final anniv = DateTime(month.year, month.month, day < dim ? day : dim);
    return anniv.isBefore(DateTime(_now.year, _now.month, _now.day));
  }

  /// Quitação do atraso (tesoureiro/dono) — para quem paga aos poucos: um único
  /// campo de valor (default = total devido) que abate os meses vencidos do MAIS
  /// ANTIGO para o mais novo, deixando o parcial na cota seguinte.
  ///
  /// Toda a matemática vem de `Caixinha.planCotaSettlement` (pura e testada), que
  /// garante o invariante: a dívida cai exatamente o valor pago. O juro que deixa
  /// de ser derivável sem ter sido pago é **cristalizado** e continua devido.
  Future<void> _quitarAtraso(BuildContext context, Caixinha c, CaixinhaMember m) async {
    final pid = m.person.id;
    final arrears = c.cotaArrearsOf(pid, now: _now);
    if (!arrears.isLate) return;
    final name = pid == 'me' ? 'Você' : m.person.fullName;

    bool comJuros = true;
    final pagoCtrl = TextEditingController(text: Money.plain(arrears.total));
    CotaSettlementPlan plan() => c.planCotaSettlement(
          pid,
          amount: Money.parse(pagoCtrl.text) ?? 0,
          chargeInterest: comJuros,
          now: _now,
        );

    final ok = await _sheet<bool>(context, 'Quitar · $name', (ctx, setSheet) {
      final theme = Theme.of(ctx);
      final p = plan();
      return [
        _KvRow('Cotas em atraso', Money.format(arrears.principal)),
        if (arrears.carriedInterest > 0.005) _KvRow('Juros pendentes (já cobrados)', Money.format(arrears.carriedInterest)),
        _KvRow('Juros do atraso', Money.format(arrears.derivedInterest)),
        const Divider(height: 20),
        _KvRow('Total devido', Money.format(arrears.total), strong: true),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Estava atrasado')),
            ButtonSegment(value: false, label: Text('Pagou em dia')),
          ],
          selected: {comJuros},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setSheet(() {
            comJuros = s.first;
            pagoCtrl.text = Money.plain(comJuros ? arrears.total : arrears.principal);
          }),
        ),
        const SizedBox(height: 6),
        Text(
          comJuros
              ? 'Cobra os juros do atraso (viram rendimento da caixinha).'
              : 'Correção de registro: lança os aportes datados nos meses e perdoa os juros deles.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: pagoCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setSheet(() {}),
          decoration: const InputDecoration(
            labelText: 'Valor a pagar',
            prefixText: r'R$ ',
            helperText: 'Abate dos meses mais antigos pra frente. Pode pagar parcial — o resto continua devendo.',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.mentaViva.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.isEmpty
                    ? 'Valor insuficiente pra lançar.'
                    : [
                        if (p.monthsCleared > 0) 'Quita ${p.monthsCleared} cota(s) cheia(s)',
                        if (p.partialAmount > 0.005) 'parcial de ${Money.format(p.partialAmount)} em ${_label(p.partialMonth!)}',
                        if (p.interestPaid > 0.005) '${Money.format(p.interestPaid)} de juros',
                      ].join(' + '),
                style: theme.textTheme.bodyMedium,
              ),
              // O ponto central: juro que sai do cálculo sem ser pago NÃO some.
              if (p.newCharge > 0.005) ...[
                const SizedBox(height: 4),
                Text('${Money.format(p.newCharge)} de juros ficam registrados como pendentes (continuam devidos).',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.coralAceso)),
              ],
              if (p.remainingDebt > 0.005) ...[
                const SizedBox(height: 2),
                Text('Continua devendo ${Money.format(p.remainingDebt)}.', style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ];
    }, confirmLabel: 'Registrar quitação', controllers: [pagoCtrl]);

    if (ok == true) {
      final p = plan();
      if (p.isEmpty && p.newCharge <= 0.005) return;
      await widget.ref.read(repositoryControllerProvider).settleCotaArrears(
            c.id,
            personId: pid,
            contributions: [for (final f in p.fills) (date: c.dueDateOfMonth(f.month), amount: f.amount)],
            interestPaid: p.interestPaid,
            chargePayments: p.chargePayments,
            newCharge: p.newCharge,
          );
    }
  }

  /// Registro editável da cota de UM mês (parte da reconstrução do histórico):
  /// valor e data na mão. É lançamento de aporte na competência do mês — NÃO
  /// cobra juros (para isso existe "Quitar atraso"). Serve pro tesoureiro trazer
  /// um mês passado que aparece "atrasado" mas foi pago em dia, com a data real.
  Future<void> _registrarCotaMes(BuildContext context, Caixinha c, CaixinhaMember m, DateTime month, double pending) async {
    final pid = m.person.id;
    final name = pid == 'me' ? 'Você' : m.person.fullName;
    final quota = c.suggestedAporteFor(pid);
    final paidSoFar = c.contributedInMonth(pid, month);
    // Data padrão: o vencimento daquele mês (ou hoje, se for o mês corrente).
    final day = c.paymentDay ?? 15;
    final dim = DateTime(month.year, month.month + 1, 0).day;
    DateTime date = _same(month, DateTime(_now.year, _now.month))
        ? _now
        : DateTime(month.year, month.month, day < dim ? day : dim);
    final valorCtrl = TextEditingController(text: pending > 0 ? Money.plain(pending) : '');
    final ok = await _sheet<bool>(context, 'Cota de ${_label(month)} · $name', (ctx, setSheet) => [
          Text('Cota do mês: ${Money.format(quota)}. Já aportou ${Money.format(paidSoFar)}. '
              'Lance o que falta com a data real — sem juros (é aporte, não quitação de atraso).',
              style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 14),
          TextField(
            controller: valorCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor aportado', prefixText: r'R$ '),
          ),
          const SizedBox(height: 12),
          _DateRow(value: date, floor: DateTime(2020), onChanged: (d) => setSheet(() => date = d)),
        ], confirmLabel: 'Registrar aporte', controllers: [valorCtrl]);
    if (ok == true) {
      final v = Money.parse(valorCtrl.text) ?? 0;
      if (v > 0) {
        await widget.ref.read(repositoryControllerProvider).addContribution(c.id, personId: pid, amount: v, date: date);
      }
    }
  }
}

/// Linha "chave: valor" usada nos diálogos (ex.: resumo da quitação).
class _KvRow extends StatelessWidget {
  final String k;
  final String? v;
  final bool strong;
  const _KvRow(this.k, this.v, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(k, style: theme.textTheme.bodyMedium)),
          Text(v ?? '', style: strong ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Linha de um participante em atraso: cotas vencidas + juros + botão de quitar.
class _ArrearsRow extends StatelessWidget {
  final String name;
  final CotaArrears arrears;
  final VoidCallback? onQuitar;
  const _ArrearsRow({required this.name, required this.arrears, this.onQuitar});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.coralAceso.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.clockCountdown, size: 18, color: AppColors.coralAceso),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleMedium),
                    Text(
                      '${arrears.months} mês(es) vencido(s) · ${Money.format(arrears.principal)}'
                      '${arrears.hasInterest ? ' + ${Money.format(arrears.interest)} de juros' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('deve', style: theme.textTheme.bodySmall),
                  MoneyText(arrears.total, fontSize: 15, color: AppColors.coralAceso),
                ],
              ),
            ],
          ),
          if (onQuitar != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: onQuitar, child: const Text('Quitar atraso')),
            ),
          ],
        ],
      ),
    );
  }
}

/// Linha compacta de um participante que já saiu da caixinha (histórico).
class _ExitedRow extends StatelessWidget {
  final Caixinha c;
  final CaixinhaMember member;
  const _ExitedRow({required this.c, required this.member});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = member.person.id == 'me';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(AppIcons.signOut, size: 16, color: AppColors.textoSuave),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${isMe ? 'Você' : member.person.fullName} saiu · recebeu de volta',
                style: theme.textTheme.bodySmall),
          ),
          MoneyText(c.exitRefundOf(member.person.id), fontSize: 13),
        ],
      ),
    );
  }
}

class _LoanRow extends StatelessWidget {
  final Caixinha c;
  final Loan loan;
  final WidgetRef ref;
  const _LoanRow({required this.c, required this.loan, required this.ref});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outstanding = c.outstandingOf(loan);
    final accrued = c.accruedInterestOf(loan.id);
    final repaid = c.repaidOf(loan.id);
    final settled = c.isSettled(loan);
    final writtenOff = c.isWrittenOff(loan);
    final internal = c.loanIsInternal(loan);
    final payments = c.paymentsOf(loan.id);
    final canManage = c.iAmTreasurer && c.isOpen && !settled;

    return Opacity(
      opacity: settled ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: AppColors.areiaNeutra),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(AppIcons.handshake, size: 18, color: AppColors.textoSuave),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${loan.borrowerName} ${internal ? '(membro)' : '(de fora)'}',
                          style: theme.textTheme.titleMedium),
                      Text(
                        writtenOff
                            ? 'Perda — ${loan.borrowerName.split(' ').first} não pagou'
                            : settled
                                ? 'Quitado · pagou ${Money.format(repaid)}'
                                : 'Pegou ${Money.format(loan.principal)} · ${_pct(loan.interestPct)}/mês'
                                    '${accrued > 0 ? ' · ${Money.format(accrued)} juros' : ''}'
                                    '${repaid > 0 ? ' · pagou ${Money.format(repaid)}' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(color: writtenOff ? AppColors.coralAceso : null),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(writtenOff ? 'perda' : (settled ? 'quitado' : 'deve'), style: theme.textTheme.bodySmall),
                    MoneyText(outstanding, fontSize: 15),
                  ],
                ),
              ],
            ),
            // Histórico de pagamentos (o tomador também vê isso na Etapa 2).
            if (payments.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final p in payments)
                Padding(
                  padding: const EdgeInsets.only(left: 26, bottom: 2),
                  child: Row(
                    children: [
                      Icon(AppIcons.check, size: 12, color: AppColors.verdeAguaProfundo),
                      const SizedBox(width: 6),
                      Text('Pagou ${Money.format(p.amount)}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
            ],
            if (canManage) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _editar(context),
                    icon: Icon(AppIcons.pencilSimple, size: 16),
                    label: const Text('Editar valor/data'),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), visualDensity: VisualDensity.compact),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _marcarPerda(context),
                    icon: Icon(AppIcons.warningCircle, size: 16),
                    label: const Text('Marcar como perda'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.coralAceso,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _lancarJuros(context),
                      child: const Text('Juros do mês'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _registrarPagamento(context),
                      child: const Text('Registrar pagamento'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _lancarJuros(BuildContext context) async {
    // Sugestão: juros sobre o SALDO DEVEDOR atual (o remanescente acumula juros).
    final base = c.outstandingOf(loan);
    final suggested = double.parse((base * loan.interestPct / 100).toStringAsFixed(2));
    DateTime date = DateTime.now();
    final ctrl = TextEditingController(text: Money.plain(suggested));
    final ok = await _sheet<bool>(context, 'Juros do mês', (ctx, setSheet) => [
          Text('${loan.borrowerName} · ${_pct(loan.interestPct)} sobre o saldo devedor de ${Money.format(base)}.',
              style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Juros a lançar', prefixText: r'R$ '),
          ),
          const SizedBox(height: 12),
          _DateRow(value: date, floor: c.createdAt, onChanged: (d) => setSheet(() => date = d)),
        ], confirmLabel: 'Lançar rendimento', controllers: [ctrl]);
    if (ok == true) {
      final amount = Money.parse(ctrl.text) ?? 0;
      if (amount > 0) {
        await ref.read(repositoryControllerProvider).recordLoanInterest(c.id, loan.id, amount, date: date);
      }
    }
  }

  Future<void> _registrarPagamento(BuildContext context) async {
    final outstanding = c.outstandingOf(loan);
    DateTime date = DateTime.now();
    // Vem preenchido com o saldo total (quitação); dá pra reduzir p/ parcial.
    final ctrl = TextEditingController(text: Money.plain(outstanding));
    final ok = await _sheet<bool>(context, 'Registrar pagamento', (ctx, setSheet) => [
          Text('${loan.borrowerName} deve ${Money.format(outstanding)}. Pode pagar tudo ou uma parte — '
              'o que sobrar continua rendendo juros.', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor pago', prefixText: r'R$ '),
          ),
          const SizedBox(height: 12),
          _DateRow(value: date, floor: c.createdAt, onChanged: (d) => setSheet(() => date = d)),
        ], confirmLabel: 'Registrar', controllers: [ctrl]);
    if (ok == true) {
      final amount = Money.parse(ctrl.text) ?? 0;
      if (amount > 0) {
        await ref.read(repositoryControllerProvider).addLoanPayment(c.id, loan.id, amount: amount, date: date);
      }
    }
  }

  Future<void> _editar(BuildContext context) async {
    final principalCtrl = TextEditingController(text: Money.plain(loan.principal));
    final interestCtrl = TextEditingController(text: _pctPlain(loan.interestPct));
    DateTime date = loan.date;
    final ok = await _sheet<bool>(context, 'Editar empréstimo', (ctx, setSheet) => [
          Text('Ajuste valor, juros e data — útil pra reconciliar um empréstimo do passado.',
              style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: principalCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor emprestado', prefixText: r'R$ '),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: interestCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Juros ao mês', suffixText: '%'),
          ),
          const SizedBox(height: 12),
          _DateRow(value: date, floor: c.createdAt, onChanged: (d) => setSheet(() => date = d)),
        ], confirmLabel: 'Salvar', controllers: [principalCtrl, interestCtrl]);
    if (ok == true) {
      final principal = Money.parse(principalCtrl.text);
      final interest = double.tryParse(interestCtrl.text.replaceAll(',', '.'));
      await ref.read(repositoryControllerProvider).updateLoan(c.id, loan.id, principal: principal, interestPct: interest, date: date);
    }
  }

  Future<void> _marcarPerda(BuildContext context) async {
    final loss = c.outstandingOf(loan);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Marcar como perda?'),
        content: Text('${loan.borrowerName} não vai pagar. O saldo devedor de ${Money.format(loss)} entra '
            'como prejuízo e é distribuído entre todos, proporcional à participação.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.coralAceso),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Marcar perda'),
          ),
        ],
      ),
    );
    if (ok == true && loss > 0) {
      await ref.read(repositoryControllerProvider).addEarning(
            c.id,
            amount: -loss,
            source: EarningSource.loanInterest,
            loanId: loan.id,
            note: 'Perda — ${loan.borrowerName} não pagou',
          );
    }
  }
}


class _ClosedBanner extends StatelessWidget {
  final Caixinha c;
  const _ClosedBanner({required this.c});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.mentaViva.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Row(
        children: [
          Icon(AppIcons.checkCircle, color: AppColors.verdeAguaProfundo),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Caixinha encerrada. Veja abaixo a parte de cada um na partilha.',
                style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Guia de preenchimento para caixinhas migradas ("já em andamento"): três
/// passos que abrem os fluxos já existentes (cotas mês a mês, rendimentos e
/// empréstimos), na ordem que faz a conta bater. Dispensável.
class _OnboardingGuide extends StatelessWidget {
  final VoidCallback onCotas;
  final VoidCallback onRendimento;
  final VoidCallback onEmprestimo;
  final VoidCallback onDismiss;
  const _OnboardingGuide({
    required this.onCotas,
    required this.onRendimento,
    required this.onEmprestimo,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      decoration: BoxDecoration(
        color: AppColors.mentaViva.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.verdeAguaProfundo.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIconsFill.usersThree, size: 20, color: AppColors.verdeAguaProfundo),
              const SizedBox(width: 8),
              Expanded(child: Text('Preencher o histórico', style: theme.textTheme.titleMedium)),
              InkWell(
                borderRadius: BorderRadius.circular(100),
                onTap: onDismiss,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(AppIcons.close, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: Text(
              'Caixinha que já rodava? Traga o passado pra dentro na ordem abaixo — o app calcula '
              'participação, juros e rendimento. Se já informou o saldo de hoje na criação, pule as cotas.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          _GuideStep(n: '1', icon: AppIconsFill.coins, title: 'Revisar cotas mês a mês', subtitle: 'Marque quem pagou em cada mês', onTap: onCotas),
          _GuideStep(n: '2', icon: AppIcons.trendingUp, title: 'Lançar rendimentos', subtitle: 'O que rendeu no banco em cada mês', onTap: onRendimento),
          _GuideStep(n: '3', icon: AppIcons.handshake, title: 'Registrar empréstimos', subtitle: 'Com a data real — os juros retroativos entram sozinhos', onTap: onEmprestimo),
        ],
      ),
    );
  }
}

/// Um passo do guia de preenchimento: número + ícone + título/subtítulo, tocável.
class _GuideStep extends StatelessWidget {
  final String n;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _GuideStep({required this.n, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.verdeAguaProfundo, shape: BoxShape.circle),
              child: Text(n, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Icon(icon, size: 18, color: AppColors.verdeAguaProfundo),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Icon(AppIcons.caretRight, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}

/// Lançamentos disponíveis no botão flutuante (só dono/tesoureiro).
enum _AcaoLancamento { aporte, rendimento, emprestimo }

/// Rótulo de aba com contador opcional (ex.: quantas pessoas devendo).
class _TabLabel extends StatelessWidget {
  final String text;
  final int badge;
  final bool subtle;
  const _TabLabel({required this.text, this.badge = 0, this.subtle = false});

  @override
  Widget build(BuildContext context) {
    if (badge <= 0) return Text(text);
    final color = subtle ? AppColors.verdeAguaProfundo : AppColors.coralAceso;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(100)),
          child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Botão flutuante de lançamentos: abre as três ações (aporte, rendimento,
/// empréstimo) numa folha. Só é construído para dono/tesoureiro.
class _LancarFab extends StatelessWidget {
  final ValueChanged<_AcaoLancamento> onSelected;
  const _LancarFab({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      backgroundColor: AppColors.verdeAguaProfundo,
      foregroundColor: Colors.white,
      onPressed: () => _menu(context),
      icon: Icon(AppIcons.plus),
      label: const Text('Lançar'),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final escolha = await showModalBottomSheet<_AcaoLancamento>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: Theme.of(ctx).scaffoldBackgroundColor,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                child: Row(
                  children: [
                    Expanded(child: Text('Lançar', style: Theme.of(ctx).textTheme.titleLarge)),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: Icon(AppIcons.close),
                    ),
                  ],
                ),
              ),
              _FabOption(
                icon: AppIconsFill.coins,
                title: 'Aporte',
                subtitle: 'Dinheiro que entrou de um participante',
                onTap: () => Navigator.of(ctx).pop(_AcaoLancamento.aporte),
              ),
              _FabOption(
                icon: AppIcons.trendingUp,
                title: 'Rendimento',
                subtitle: 'Resultado do mês (banco/poupança)',
                onTap: () => Navigator.of(ctx).pop(_AcaoLancamento.rendimento),
              ),
              _FabOption(
                icon: AppIcons.handshake,
                title: 'Emprestar',
                subtitle: 'Registrar valor emprestado a alguém',
                onTap: () => Navigator.of(ctx).pop(_AcaoLancamento.emprestimo),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (escolha != null) onSelected(escolha);
  }
}

class _FabOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _FabOption({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.mentaViva.withValues(alpha: 0.25),
        child: Icon(icon, color: AppColors.verdeAguaProfundo, size: 20),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      onTap: onTap,
    );
  }
}

/// Linha detalhada do histórico (aba Histórico): o que foi lançado, para quem,
/// por quem, o valor e o patrimônio ANTES → DEPOIS da movimentação.
class _MovementCard extends StatelessWidget {
  final CaixinhaMovement movement;

  /// Ação de desfazer — só chega preenchida para o dono (ver `_tabHistorico`).
  final VoidCallback? onUndo;
  const _MovementCard({required this.movement, this.onUndo});

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = movement;
    final positive = m.amount >= 0;
    final loss = m.kind == MovementKind.earning && m.amount < 0;
    final (IconData icon, Color color) = loss
        ? (AppIconsFill.warningCircle, AppColors.coralAceso)
        : switch (m.kind) {
            MovementKind.contribution => (AppIconsFill.coins, AppColors.verdeAguaProfundo),
            MovementKind.earning => (AppIcons.trendingUp, AppColors.verdeAguaProfundo),
            MovementKind.adjustment => (AppIcons.pencilSimple, AppColors.textoSuave),
            MovementKind.exit => (AppIcons.signOut, AppColors.coralAceso),
          };
    final antes = m.balanceAfter - m.amount;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(m.label, style: theme.textTheme.titleMedium)),
              Text('${positive ? '+' : '−'} ${Money.format(m.amount.abs())}',
                  style: AppTheme.moneyStyle(
                      fontSize: 15, color: positive ? AppColors.verdeAguaProfundo : AppColors.coralAceso)),
            ],
          ),
          const SizedBox(height: 8),
          _kv(theme, 'Quando', _fmtDate(m.date)),
          _kv(theme, 'Lançado por', m.recordedByName ?? 'a própria pessoa'),
          _kv(theme, 'Patrimônio', '${Money.format(antes)}  →  ${Money.format(m.balanceAfter)}'),
          if (onUndo != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.coralAceso,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: onUndo,
                icon: Icon(AppIcons.undo, size: 16),
                label: const Text('Desfazer'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) => Padding(
        padding: const EdgeInsets.only(left: 28, top: 2),
        child: Row(
          children: [
            Expanded(child: Text(k, style: theme.textTheme.bodySmall)),
            Text(v, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// Enquadramento legal: o app só organiza; não é instituição financeira.
class _OrganizerDisclaimer extends StatelessWidget {
  const _OrganizerDisclaimer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.mentaViva.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: 16, color: AppColors.verdeAguaProfundo),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'O Fechaí organiza finanças pessoais entre pessoas de confiança. Não é '
              'instituição financeira: não empresta, não cobra e não guarda dinheiro. '
              'Os valores e as taxas são combinados entre vocês.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Seletor de data para os lançamentos: default hoje, não deixa escolher antes
/// da abertura da caixinha ([floor]) nem no futuro.
class _DateRow extends StatelessWidget {
  final DateTime value;
  final DateTime floor;
  final ValueChanged<DateTime> onChanged;
  const _DateRow({required this.value, required this.floor, required this.onChanged});

  String get _text => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final now = DateTime.now();
        var first = DateTime(floor.year, floor.month, floor.day);
        // Nunca deixa o piso passar de hoje (senão showDatePicker estoura com
        // firstDate > lastDate quando o início é hoje/futuro).
        if (first.isAfter(now)) first = DateTime(now.year, now.month, now.day);
        var init = value;
        if (init.isBefore(first)) init = first;
        if (init.isAfter(now)) init = now;
        final picked = await showDatePicker(context: context, initialDate: init, firstDate: first, lastDate: now);
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.areiaNeutra),
        ),
        child: Row(
          children: [
            Icon(AppIconsFill.calendarBlank, size: 18, color: AppColors.verdeAguaProfundo),
            const SizedBox(width: 10),
            Expanded(child: Text('Data do lançamento', style: theme.textTheme.bodyMedium)),
            Text(_text, style: theme.textTheme.titleMedium),
            const SizedBox(width: 4),
            Icon(AppIcons.caretRight, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;
  const _EmptyLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// Visão do TOMADOR EXTERNO: enxerga só o nome da caixinha e o(s) próprio(s)
/// empréstimo(s) — quanto pegou, quanto deve e o histórico de pagamento. Não vê
/// aportes, saldos nem outros membros (a RLS também garante isso no servidor).
class _BorrowerScreen extends StatelessWidget {
  final Caixinha c;
  const _BorrowerScreen({required this.c});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myLoans = c.loans.where((l) => l.borrowerPersonId == 'me').toList();
    final totalOwed = myLoans.fold(0.0, (a, l) => a + c.outstandingOf(l));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: Icon(AppIcons.arrowLeft), onPressed: () => context.go('/caixinhas')),
        title: Row(
          children: [
            Text(c.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          WaveCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Você ainda deve',
                    style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Text(Money.format(totalOwed), style: AppTheme.moneyStyle(fontSize: 36, color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (myLoans.isEmpty)
            _EmptyLine(text: 'Você não tem empréstimos nesta caixinha.'),
          for (final l in myLoans) _BorrowerLoanCard(c: c, loan: l),
          const SizedBox(height: 12),
          Text(
            'Você participa desta caixinha apenas como tomador de empréstimo. '
            'Os valores dos outros participantes não ficam visíveis para você.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BorrowerLoanCard extends StatelessWidget {
  final Caixinha c;
  final Loan loan;
  const _BorrowerLoanCard({required this.c, required this.loan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outstanding = c.outstandingOf(loan);
    final accrued = c.accruedInterestOf(loan.id);
    final repaid = c.repaidOf(loan.id);
    final payments = c.paymentsOf(loan.id);
    final settled = c.isSettled(loan);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.areiaNeutra),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(settled ? 'Empréstimo quitado' : 'Seu empréstimo', style: theme.textTheme.titleLarge),
              const Spacer(),
              if (settled) const _SettledChip(),
            ],
          ),
          const SizedBox(height: 12),
          _kv(theme, 'Pegou', Money.format(loan.principal)),
          _kv(theme, 'Juros combinado', '${_pct(loan.interestPct)} ao mês'),
          if (accrued > 0) _kv(theme, 'Juros acumulados', Money.format(accrued)),
          if (repaid > 0) _kv(theme, 'Já pagou', Money.format(repaid)),
          const Divider(height: 24),
          Row(
            children: [
              Text('Saldo devedor', style: theme.textTheme.titleMedium),
              const Spacer(),
              MoneyText(outstanding, fontSize: 18),
            ],
          ),
          if (payments.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Histórico de pagamentos', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final p in payments)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(AppIcons.checkCircle, size: 16, color: AppColors.verdeAguaProfundo),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p.note?.isNotEmpty == true ? p.note! : 'Pagamento', style: theme.textTheme.bodyMedium)),
                    MoneyText(p.amount, fontSize: 14, color: AppColors.verdeAguaProfundo),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(k, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(v, style: AppTheme.moneyStyle(fontSize: 14, color: AppColors.tintaProfunda)),
          ],
        ),
      );
}

/// Pequeno selo "Quitado" reutilizando o visual dos chips.
class _SettledChip extends StatelessWidget {
  const _SettledChip();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.verdeAguaProfundo.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
        child: const Text('Quitado', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.verdeAguaProfundo)),
      );
}
