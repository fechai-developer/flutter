# Fechaí — TODO de implementação

> **Estado:** o app está funcional rodando com **mock** (`flutter run`) e com o
> **Supabase real** (`flutter run --dart-define=USE_SUPABASE=true`). As Etapas 1 e 2
> foram **validadas em runtime pelo usuário** (login com contas de teste + CRUD real
> ponta a ponta). As próximas etapas estão descritas abaixo.

Cada etapa é um "pode fazer" e o assistente implementa. Só a **Etapa Final (login/produção)**
e o **deploy das Edge Functions** exigem configuração do usuário no painel Supabase.

---

## ✅ Etapa 1 — App funcional (mock) — FEITO
- Grupos: criar, **editar** (nome/emoji/juros/membros), **excluir** (dono), lançar/**editar/excluir** despesa, **divisão** igual/%/partes/valor exato, **despesa recorrente** (captura da intenção).
- Saldos simplificados + **acerto real** ("Já paguei" / "Já recebi" zeram a dívida; só as 2 pessoas envolvidas acertam).
- **Cobra Aí** (WhatsApp + PIX copia-e-cola + QR) e **Pagar** (PIX do recebedor). Hub **Cobrar** com "Cobrar todos" e tag Conta/Assinatura.
- Assinaturas: criar/**editar**, cotas, status, **adicionar participante**, **juros que acrescem no atraso**.
- **Juros até 20% ilustrativos** (disclaimer vermelho > 1%); **termo de uso** no login.
- **Resumo** (gráfico pago x recebido/mês); logo **onda + R$**.
- UX: **busca + filtro por pessoa e por status** (60/20/20), **tags de status** + ordenação + dimming nas listas, **feed de atividade** com crédito/débito, **nomes sublinhados**, **máscaras** (telefone/CPF) e **campo de chave PIX** com tipo/validação, **emoji custom** (teclado), **sugestão de membros conhecidos**, **selo de "não aceitou o convite"**.
- Testes: `flutter test` (divisão, PIX/CRC16, juros, acerto de saldo).

## ✅ Etapa 2 — Dados reais no Supabase (código) — FEITO e VALIDADO
- `SupabaseRepository` (CRUD real, tradução `me`↔`auth.uid()`), login e-mail+senha, completar perfil no 1º acesso, guard de rota.
- Migrações **aplicadas** no projeto: schema inicial, `payments`, `months_late`, `recurrence`, vínculo por telefone.
- **Seed de teste** pronto (`supabase/seed_test.sql`) + usuários padrão (`voce@/ana@/bruno@fechai.test`, senha `Fechai123!`).
- ✅ **Validado em runtime pelo usuário**: login com contas de teste + CRUD real ponta a ponta. Ver `fechai-docs/TESTING.md`.
- [ ] Consumir `payee_info` no fluxo Pagar quando a chave do recebedor não veio localmente (parcial: `memberPixKey` já resolve via RPC).

---

## ⏭️ A FAZER quando retomar

### ✅ Etapa C — Convite / Social — FEITO (validado no mock; falta rodar no Supabase real)
Fechou o ciclo de convite. Status por membro no modelo (`MemberStatus {pending,accepted,declined}`
em `person.dart`; `ExpenseGroup.memberStatus` e `SubscriptionMember.inviteStatus`) + status
`declined` no banco (migração `20260721160000_declined_status.sql`).
- [x] **Aceitar/Recusar na lista** (item 5): convites com **Aceitar/Recusar** em 3 lugares —
  banner da Home, lista de **grupos** e lista de **assinaturas** (via `InviteActionBar` +
  `PendingInvite.sourceId` casando o convite com o card). No banner, "Recusar" fica à direita,
  abaixo de "Aceitar". Ordenação das listas de **membros** é **alfabética** (você primeiro) — a
  não-aceitação é sinalizada pelo indicador, não pela posição (dois conhecidos podem não ter
  aceitado o grupo novo).
- [x] **Estado "recusado"** (item 6): ao recusar, o convite continua listado (esmaecido + tag
  "Recusado" + aceitar depois). Membro recusado aparece esmaecido (`DeclinedDim`) nas listas.
- [x] **Nome entre aspas + indicação explícita** (item 9): nome digitado entre "aspas" itálicas
  enquanto não aceito; **apenas negrito** (sem sublinhado) após aceite. Indicação além das aspas:
  **ampulheta com tooltip** "Aguardando o aceite do convite" (pendente) e **tag "Recusado"**
  (`core/widgets/member_name.dart` + `PendingBadge`).
  - ✅ _Feito (sessão 2026-07-22):_ o nome exibido passa a ser o **real da pessoa** após o aceite —
    ver seção "Nome + Sobrenome" abaixo (gatilhos `stamp_real_name`/`propagate_profile_name`).
- [x] **Convite via WhatsApp**: botão "Convidar" (grupo e assinatura) monta a mensagem com link de
  entrada (`WhatsApp.inviteMessage`). O vínculo por telefone religa quem se cadastra depois.
- [x] **Conhecidos com nome + telefone** (itens 4/5): `KnownMembersPicker` (compartilhado)
  sugere pessoas de outros grupos/assinaturas mostrando **nome e telefone**. A criação de
  **assinatura** agora também adiciona participantes (antes só no detalhe), igual ao grupo.
- [ ] **Deferido — Importar da agenda (mobile)**: exige pacote nativo (`flutter_contacts`) +
  permissões de runtime; não validável no ambiente web atual.
- [ ] **Deferido — Redenção do deep link (token/RLS)**: pertence à Etapa S (Segurança). Hoje o
  link é informativo; o religamento automático por telefone já cobre o essencial.
- [ ] Cobrança só depois do aceite: já refletido na UI (botão "Convidar" no lugar de "Cobra Aí"
  enquanto não aceito). Reforçar no servidor (RLS/Edge Function) fica na Etapa S/Fase E.

### ✅ Remoção de membro com preservação de histórico — FEITO (mock + testes; falta aplicar migração no Supabase)
Remover alguém de grupo/assinatura sem punir quem participou. Regra (validada em `test/member_removal_test.dart`):
- [x] **Trava de saldo no servidor**: só remove quem está zerado (grupo: `netBalances`=0; assinatura: cota quitada).
  RPCs `remove_group_member` / `remove_subscription_member` (SECURITY DEFINER) autorizam **dono ou o próprio** (auto-saída).
- [x] **Nunca teve movimentação → hard delete** (some). **Já teve → soft** (`removed_at`): sai das movimentações
  ativas, mas mantém acesso **somente-leitura** ao histórico das despesas em que se envolveu + consolidado.
- [x] **RLS**: `is_group_member`/`is_sub_member` passam a contar **só ativos** (removido perde leitura ampla e
  escrita); `was_group_member`/`was_sub_member` + `involved_in_expense` devolvem o acesso pontual ao histórico;
  `shares_context_with` exige `removed_at is null` (removido para de expor/receber nome+PIX).
- [x] **UI**: estado **"Arquivado"** (cadeado, esmaecido) nas listas + detalhe **só-leitura**; subseção
  **"Ex-participantes"**; botão **"Sair do grupo/assinatura"** (não-dono); remover participante na assinatura.
- [x] **Recorrência afetada por saída** (`expenses.recurrence_review`, migração `20260722140000`): ao remover/sair,
  a RPC marca as despesas **recorrentes** do grupo — `participantLeft` (participante do rateio saiu → aviso) ou
  `payerLeft` (quem pagava saiu → bloqueia). UI mostra **pílula na despesa** + **banner nos Saldos** (dono); editar a
  despesa zera o flag. **Regra p/ a geração automática (Fase E) consumir** — a redistribuição **NÃO depende** de o
  dono editar/salvar; é keyed no `group_members.removed_at`: ao gerar a próxima ocorrência, **filtrar `expense_shares`
  pelos membros ativos e redividir entre eles** (o flag/badge é só aviso, não pré-requisito). Se `payerLeft`, **não
  gerar** aquela série até o dono reatribuir o pagador (não dá pra escolher quem adianta o dinheiro sozinho). Como o
  soft-remove exige saldo zerado, não há dívida pendente da pessoa que saiu.
- [x] **Migrações aplicadas** no Supabase (`20260722120000_member_removal` e `20260722140000_recurrence_review`).
- [ ] **Auditar RLS com 2 usuários**: o removido só enxerga as próprias despesas; um terceiro ativo continua vendo
  tudo; removido não insere despesa/acerto.

### ✅ Etapa D — Saldos consolidados & refino de UX — FEITO (validado no mock via preview)
Lote de UX/produto sobre a base pronta. Tudo com `flutter test` verde e `flutter analyze` limpo.

- [x] **Tela "Acertar" (substitui a aba "Cobrar")** — consolida, **pessoa a pessoa**, tudo o que me
  devem e tudo o que devo, **somando grupos + assinaturas** (`ConsolidatedBalances` em
  `lib/core/utils/consolidated_balance.dart`; tela `features/charge/settle_screen.dart`). Usa a
  mesma simplificação dos grupos (me↔pessoa) e agrupa a mesma pessoa entre origens **pelo telefone**.
  - **Quitar de uma vez só**: "Já recebi tudo" / "Já paguei tudo" registram o acerto em **cada
    grupo** e marcam as **cotas** — um toque acerta a pessoa em todas as origens.
  - **FAB "Cobrar tudo (N)"** (canto inferior direito) dispara um WhatsApp por credor com o total.
  - Cobrar/Pagar são **ações dentro** da tela (folha de detalhe por pessoa com a quebra por origem).
  - **Acesso pela Home**: o card de saldo (a receber/a pagar) agora é **tocável** e leva ao Acertar.
  - Cobertura: `test/consolidated_balance_test.dart` (consolidação por telefone, netagem, cotas).
- [x] **Navegação reordenada**: `Início · Acertar · Contas · Assinaturas` (Acertar logo após Início),
  ícone de **dinheiro** (`AppIcons.payments`) no lugar da mão-com-coração. _Phosphor `hand-coins`
  segue o alvo quando o pacote suportar Flutter 3.44._
- [x] **Cobrar/Pagar com PIX de cara + gavetas**: as folhas mostram o **PIX copia e cola de cara**;
  **QR Code** e **mensagem do WhatsApp** ficam em **gavetas** (`ExpandableTile`). Na cobrança:
  "Mostrar seu QR Code PIX para recebimento". No **Pagar**: gaveta "Ver QR Code de {nome} para
  escanear" (apontar a câmera do banco na tela). Widgets novos: `core/widgets/expandable_tile.dart`,
  `core/widgets/pix_qr.dart`.
- [x] **Participantes visíveis** nos detalhes: faixa `ParticipantsStrip` (avatares + contagem, toque
  abre a lista com status aceito/pendente/recusado) no detalhe do **grupo**; **avatares** no card da
  lista de **assinaturas** (paridade com grupos).
- [x] **Despesa recorrente com dia selecionável (1–27)**: ao ligar a chave, escolhe o dia do mês
  (antes era fixo). Campo `Expense.recurrenceDay`; migração `20260721180000_recurrence_day.sql`.
- [x] **Tema claro moderno** (`themeMode: ThemeMode.light`): bordas hairline, sombra difusa em 2
  camadas, cantos maiores, texto secundário mais suave; nomes de usuário só **negrito** (sem
  sublinhado). Detalhes em `DESIGN_SYSTEM.md` (refresh 2026-07). Tema escuro mantido para futura opção.
- [x] **Atividade recente na Home**: altura fixa (~7 cards) com **rolagem interna** + botão
  **"Carregar mais"** (base para paginar no banco depois).
- [ ] **Rodar a Etapa D no Supabase real** e aplicar a migração `20260721180000_recurrence_day.sql`
  (recorrência com dia). O consolidado e a quitação reusam `settleUp`/`setQuotaStatus` já validados.

### ✅ Nome + Sobrenome & polimento de UX — FEITO (sessão 2026-07-22)
Migração `20260721220000_last_name.sql` **aplicada pelo usuário** (validado em runtime). Restante é Dart, coberto por `flutter test` + `flutter analyze` limpo.

- [x] **Nome vs. Sobrenome no modelo** (`Person`): `name` passa a ser o **primeiro nome** (exibido por
  padrão em feed, listas, despesas); novo `lastName`; getters `fullName` e `initials` (`initialsOf`).
  `copyWith` com sentinela p/ permitir **limpar** o sobrenome. Colunas `last_name` em
  `profiles`/`group_members`/`subscription_members` (backfill dividindo o nome atual no 1º espaço).
- [x] **Avatares com 2 iniciais**: `MemberAvatar` ganha `lastName` + construtor `MemberAvatar.person(p)`;
  iniciais = 1ª letra do nome + 1ª do sobrenome (fallback desmembra nome completo legado, ignorando
  tokens sem letra tipo "(organizador)"). Threaded por todas as telas (home, perfil, listas, detalhes,
  cobrança/pagar, acertar, despesa) + pilhas de avatares passam a receber `List<Person>`.
- [x] **Nome real após "se conhecerem"** (fecha o pendente da Etapa C): gatilhos no banco —
  `stamp_real_name` (ao **aceitar** um vínculo ligado a um perfil, o nome+sobrenome sugeridos por quem
  convidou são **sobrescritos pelos reais** do perfil) e `propagate_profile_name` (editar o perfil
  propaga aos vínculos aceitos). `payee_info` agora também retorna `last_name`. Mesma regra de
  privacidade do PIX (`shares_context_with`). `delete_my_account` limpa o sobrenome (LGPD).
- [x] **Nome completo nas listas de participantes** (grupos/assinaturas): mostra nome + sobrenome —
  entre "aspas" enquanto pendente/recusado, e o real (do perfil) após o aceite. Feed/cards de lista/
  cobrança seguem só o **primeiro nome**. Perfil e "Conhecidos" mostram nome completo.
- [x] **Campos Nome + Sobrenome** em todos os formulários de entrada: cadastro inicial, edição de nome
  no **Perfil** (novo — antes só editava PIX), criar/editar grupo, criar assinatura, **"Novo
  participante"** da assinatura, criar caixinha.
- [x] **X para fechar bottom sheets** (`core/widgets/sheet_handle.dart`): alça central + **X cinza** no
  canto superior direito em editar grupo/assinatura, despesa, cobrar, pagar, novo participante e lista
  de participantes. (As telas de *criação* são páginas inteiras com seta de voltar — não precisam.)
- [x] **Bug corrigido — editar despesa por % / partes não salvava**: ao editar, os campos por pessoa
  não eram repreenchidos (só "valor exato"), a soma zerava e o botão Salvar travava. Agora reconstrói
  os inputs a partir dos shares salvos. Regressão em `test/expense_edit_test.dart` (os 3 tipos).
- [x] **Renomeação de UI "Grupos" → "Contas"** (sessão 2026-07-22): a feature de despesas de evento
  passa a se chamar **"Contas"** em toda a interface — casa com o nome do app ("fechar a conta") e
  com os cenários reais (restaurante, viagem, rolê; 1 paga e cobra o resto). Trocadas ~30 strings
  visíveis (aba, títulos, botões, labels, hints, SnackBars, tooltips, tag do Acertar, textos de
  WhatsApp/Premium/onboarding) com **concordância de gênero** (m→f: "o grupo"→"a conta", "Novo"→"Nova",
  "excluído"→"excluída"). **Só a camada de exibição** mudou: o domínio interno segue em inglês —
  modelo `ExpenseGroup`, pasta `features/groups/`, rotas `/groups`, tabelas `groups`/`group_members`
  e RLS (`is_group_member`) **intactos** (padrão domínio-em-inglês / UI-no-idioma-do-produto).
  `flutter analyze` sem erros e `flutter test` verde (60 testes). **Decisão: NÃO renomear as tabelas
  do banco** — esforço médio, mas risco alto (mexe em RLS/funções/triggers + sincronia das migrations
  com o Supabase deployado) e valor nulo (nome de tabela é invisível ao usuário).

### ✅ Caixinha — poupança coletiva + empréstimos (sessão 2026-07-22) — FEITO (mock + Supabase; migrações aplicadas)
Terceira frente do app, além de Contas e Assinaturas. Vários membros aportam mensalmente,
o dinheiro rende (banco + juros de empréstimo) e no fim o período é estendido ou partilhado.
5ª aba **"Caixinha"** 🐷 no shell + rota `/caixinhas` + quick action na Home.

- [x] **Partilha por participação (unidade × tempo)** — modelo de fundo: cada aporte compra
  unidades pelo valor da unidade do dia; cada rendimento valoriza a unidade. Justo com entradas em
  datas diferentes (quem entra depois não leva rendimento retroativo). Lógica de negócio nos getters
  de `lib/data/models/caixinha.dart` (`unitValue`, `participationOf`, `balanceOf`, `profitOf`).
- [x] **Papéis** (`CaixinhaRole`): **owner** (dono), **treasurer** (lança), **member** (contribui/acompanha),
  **borrower** (tomador externo — só empréstimo, sem aceite, visão restrita). Só tesoureiro lança.
- [x] **Aportes, rendimentos** (investimento + juros de empréstimo) e **empréstimos** com **quitação
  parcial** (saldo remanescente acumula juros; juros do mês incidem sobre o saldo devedor). Tomador
  externo cadastrado como pessoa (nome/sobrenome/telefone), cria perfil, sem "pendente".
- [x] **Saída de participante**: recebe de volta **só o que aportou** (sem rendimento); o lucro que
  deixa é diluído entre quem fica. Painel do participante (tesoureiro): cotas, tesoureiro, remover.
  Fica no histórico ("saiu · recebeu R$ X").
- [x] **Cotas por participante** (padrão 1, editável): multiplica o aporte sugerido. Definível na
  criação (stepper) e no painel do membro. Vale pra frente (não altera aportes lançados).
- [x] **Período**: início da 1ª parcela + fim opcional (`start_date`/`end_date`). Editável na criação
  e na edição. A projeção usa o período como padrão de meses.
- [x] **Projeção (estimativa)** + **Relatório PDF** (`pdf`/`printing`): extrato (resumo, partilha,
  valores emprestados) + projeção opcional. Deixa claro que é estimativa e **não considera empréstimos**.
- [x] **Enquadramento legal**: seção "Valores emprestados" + disclaimer "o Fechaí organiza finanças
  pessoais, não é instituição financeira, não empresta/cobra/guarda dinheiro". Também no rodapé do PDF.
- [x] **Backend**: migrações **aplicadas pelo usuário** — `20260722130000_caixinha.sql` (6 tabelas +
  funções SECURITY DEFINER + trigger anti-escalada + RLS por papel + realtime), `20260722160000_caixinha_exits.sql`
  (saídas + coluna `quotas`), `20260722170000_caixinha_period.sql` (datas). RLS: o **borrower** só vê o
  próprio empréstimo/pagamento; aportes/rendimentos restritos a owner/treasurer/member. Realtime escuta
  as 6 tabelas + saídas. Convite de caixinha entra no fluxo aceitar/recusar (kind `caixinha`) + badge no shell.
- [x] **Matemática validada** por invariantes em `test/caixinha_test.dart` (20 testes, incl. cenário
  complexo: entradas em datas diferentes + rendimentos + empréstimo com pagamento parcial + saída).
  Conservação de dinheiro fecha por dois caminhos independentes (unidades × fluxo de caixa bruto).
- [ ] **Smoke test de integração** no Supabase real (logado): criar → aporte → empréstimo → pagamento
  parcial → saída → relatório. (Alinhamento model↔mapping↔migração conferido estaticamente; falta runtime E2E.)
- [ ] **Gating freemium da caixinha** (deixado a pedido do usuário p/ decidir depois): `plan_limits` +
  `my_plan_status` + triggers. Juros do empréstimo **não** é premium (é core da feature).
- [ ] **Limpar a data-fim na edição** (hoje só cria/muda; `copyWith` não zera para null) e **badge de
  saída/relatório na Home** — polimentos menores.

### Etapa S — Segurança 🔒  *(antes de abrir para usuários reais)*

> **Decisões (sessão 2026-07-21)** — respondidas pelo usuário e implementadas na
> migração `20260721170000_security_hardening.sql`. Números de freemium ficam em
> `plan_limits` (editável no painel Supabase). O único ponto a **confirmar** é o teto
> mensal de "Cobra Aí" do free (assumido 30/mês para servir de gancho, sem matar a
> North Star — free continua com o botão, premium tira o limite).

**Backbone no banco — FEITO (falta aplicar `db push` + auditar com 2 usuários):**
- [x] **Não-interferência / escalada de privilégio**: só o **próprio membro** promove seu
  vínculo para `accepted` (trigger `enforce_self_accept`). Fecha o furo em que o dono
  forjava um vínculo aceito com o `uuid` de uma vítima (via `find_profile_by_phone`) para
  vazar nome+PIX pelo `payee_info`. O dono segue gerenciando os demais campos.
- [x] **Juros**: teto **rígido de 20%/mês no banco** (`check`) + **gating por plano** (só
  premium liga juros > 0). Ilustrativo + disclaimer já existente.
- [x] **Freemium no servidor** (não burlável pelo cliente): tabela `plan_limits`
  (`free`: 3 grupos **ativos**, 2 assinaturas **ativas**, 30 cobranças/mês, sem juros, sem automação;
  `premium`: +3 grupos, +2 assinaturas, cobrança ilimitada, juros, automação). Travas via
  trigger em `groups`/`subscriptions`/`charges`. **Limite conta só o que está ATIVO**
  (`archived_at is null`) — arquivar um evento encerrado libera a vaga, o histórico fica.
  Fonte da verdade do premium = `profiles.plan` + `plan_valid_until`, **alterável só por
  service_role** (trigger `guard_profile_plan` bloqueia auto-promoção). `is_premium()` p/ a UI.
- [x] **Anti-enumeração por telefone**: `find_profile_by_phone` continua só id (nunca nome),
  agora com **rate limit** (60 buscas/h por usuário logado, janela fixa) e ignora perfis
  `deleted_at`. Impede varrer listas de telefones para mapear quem tem conta. Teto mensal de
  cobranças cobre o spam de disparo.
- [x] **LGPD — excluir conta**: `delete_my_account()` **anonimiza** (nome→"Usuário removido",
  zera phone/pix/foto, `deleted_at`) preservando o histórico dos grupos onde sou dono;
  anonimiza minhas linhas de membro; apaga minhas cobranças (têm telefone de terceiros).
- [x] **LGPD — exportar dados**: `export_my_data()` devolve **só os dados do titular** em JSON
  (perfil, termos, meus vínculos, minhas cobranças, meus acertos) — sem PIX/telefone de terceiros.
- [x] **Termo versionado que bloqueia até reaceite**: `app_config.terms_version` +
  `needs_terms_acceptance()`. Bump da versão = editar `app_config` no painel.

**Freemium na UI — FEITO (validado no mock via preview):**
- [x] **Status do plano exposto ao cliente**: RPC `my_plan_status()` (migração
  `20260721210000`) → `PlanStatus` (`lib/data/models/plan_status.dart`) → `planStatusProvider`.
  Mock devolve free contando as listas locais; Supabase lê o RPC. Invalidado após criar/excluir.
- [x] **Juros travado no free**: `InterestSlider(locked: !allowInterest)` mostra slider
  desabilitado + chip **Premium** + dica "recurso Premium" que abre o upsell. Nos 4 pontos
  (criar/editar grupo e assinatura).
- [x] **Limite de criação**: banner `PremiumLockBanner` + botão desabilitado ao atingir o teto
  de grupos/assinaturas ativos (create_group / create_subscription).
- [x] **Folha de upsell reutilizável** `PremiumUpsell` + `PremiumChip` + `PremiumLockBanner`
  (`lib/core/widgets/premium.dart`), no estilo do design system (gradiente verde-água + faísca).
- [x] **Card de plano no perfil** reflete o status real (Premium ativo vs. uso "X de N").
  Resiliente: enquanto carrega mostra spinner; se o provider **falhar** (ex.: RPC ainda não
  aplicado) cai no **free** em vez de travar em "Carregando seu plano…" (bug corrigido).
- [x] **`voce@fechai.test` premium indeterminado** (migração `20260721200000`).

**Falta (UI/produto + validação):**
- [x] ~~**Aplicar** `supabase db push` das migrações de segurança/RLS~~ — aplicado pelo usuário
  (`160000`/`170000`/`180000`/`190000`).
- [ ] **Aplicar migrações do freemium** `20260721200000` (premium do `voce@fechai.test`) e
  `20260721210000` (RPC `my_plan_status`) — criadas depois do último push; sem elas o card do
  perfil fica em erro (cai no free pela correção acima). `supabase db push`.
- [ ] **Auditar RLS com 2 usuários** (A não vê nada de B) em todas as tabelas (leitura E
  escrita) + rodar o bloco de auditoria no rodapé da migração (escalada, juros, auto-premium).
- [ ] **Fluxo de assinatura do Premium** (checkout/pagamento) no perfil: hoje o CTA "Quero ser
  Premium" só sinaliza "em breve". Personalizar o perfil para assinar de fato (definir preço,
  meio de pagamento, gravar `profiles.plan`/`plan_valid_until` via service_role/Edge Function).
- [ ] Confirmar que só **nome + chave PIX** de terceiros aparecem, e **só com vínculo aceito**
  (via `payee_info`) — reconfirmar após o trigger de self-accept.
- [ ] **Disclaimers/consentimento no app** (texto):
  - Ao **entrar num grupo/assinatura**: aviso de que **seu nome + chave PIX serão
    compartilhados** com os membros (1.2).
  - Aviso de que **o app só organiza** — quem paga/recebe se entende entre si; a plataforma
    não custodia dinheiro nem confirma pagamento (1.3).
  - Aviso de que **o nome digitado por quem convida não representa a pessoa real** até ela
    aceitar e compartilhar seus próprios dados (2.1) — reforça as "aspas" já existentes.
- [ ] **UI de conta**: botão **Excluir conta** (chama `delete_my_account` + logout) e
  **Exportar meus dados** (chama `export_my_data`, baixa JSON). Guard de login deve barrar
  perfil com `deleted_at`. Reaceite de termo quando `needs_terms_acceptance()` for true.
- [ ] **Arquivar grupo/assinatura** (produto): ação de arquivar (seta `archived_at`) +
  desarquivar + filtro "ativos/arquivados" nas listas. Necessário para o limite por *ativos*
  fazer sentido (encerrou o evento → arquiva → libera vaga no plano free).
- [ ] **Upsell da cobrança (não premium)** — *ainda falta*: usar `PremiumLockBanner`/`PremiumUpsell`
  na tela **Cobrar** ao chegar no teto mensal de "Cobra Aí" e para indicar que a cobrança
  automática (D+3/D+10/D+30…) é premium. O padrão de UI já existe (feito p/ juros e limites);
  só replicar no hub de cobrança.
- [ ] **Política de privacidade** publicada (documenta base legal do tratamento de dados de
  terceiros/convidados sem conta — 2.1).
- [ ] Validar/mascarar PIX; **nunca logar chave/valores**; confirmar que só a *publishable key*
  está no client.
- [ ] Rate limit de **OTP** (fase final, quando ligar OTP).

### Etapa Final — Ligar login/produção 🎬  *(precisa de você comigo)*
- [ ] Painel: **Email provider** + template OTP com `{{ .Token }}` + **SMTP próprio** (Resend/SendGrid) — o envio nativo do free tier é limitado.
- [ ] Testar login E2E; virar `USE_SUPABASE` para produção; validar dados reais ponta a ponta.
- [ ] Gerar **ícones de launcher** (exportar 1 PNG 1024px da marca → `flutter_launcher_icons`).
- [ ] (futuro) WhatsApp OTP via Twilio Verify.

---

## 🚀 Fase E — Enhancements (PÓS-DEPLOY)  *(não bloqueiam o lançamento)*
- [x] **Geração de despesas recorrentes (item 1) — FEITO (mock + testes; falta habilitar pg_cron)**:
  função SQL **idempotente** `generate_due_recurrences(p_as_of, p_group_id)` (migração `20260722180000`, ajustada por
  `20260722190000`) + gerador Dart espelhado (`lib/core/utils/recurrence.dart`, testado). O molde é a 1ª ocorrência;
  as seguintes são despesas novas ligadas por `recurrence_parent_id`+`occurrence_period` (índice único evita duplicar).
  Gera **apenas o mês corrente** quando vence — **sem backfill retroativo** (pg_cron roda diário; mês pulado não é
  recuperado, pra evitar cobrança de surpresa). **Exclui quem saiu e redivide proporcional mantendo o total**;
  **bloqueia** a série se o pagador saiu (`payerLeft`); respeita `recurrence_until`. **100% automático via pg_cron —
  sem botão/ação do usuário.** ✅ **pg_cron habilitado + job `gerar-recorrencias` agendado** (diário, 06:00 UTC).
  Conferir com `select jobid, jobname, schedule, active from cron.job;`. _Garantir que a migração
  `20260722190000` (versão "mês corrente") foi aplicada — senão a função no banco ainda faz o catch-up antigo._
- [ ] **Cobrança automática (#9)**: `pg_cron` + **Edge Function** disparando em **D+3, D+10, D+30 e a cada 30 dias**, gravando em `charges` (alimenta North Star e o Resumo) + botão "forçar cobrança". _Você faz o `supabase functions deploy`; a secret key fica só no servidor._
- [ ] **Notificações/lembretes**: saem da cobrança automática (cron/e-mail). Push nativo (FCM/APNs) é opção futura — Supabase sozinho não faz push.
- [ ] **Relatórios/exportação** (PDF/planilha) e recursos premium do freemium (PRD seção 7).
- [ ] **Conciliação automática de PIX** (webhook de PSP) — já era v2 no PRD (seção 6).

---

## O que o assistente vai te pedir (nas etapas que dependem de você)
1. **Etapa Final:** Email provider + SMTP no painel.
2. **Fase E (deploy):** `supabase functions deploy` das Edge Functions (assistente escreve, você aplica).
3. Validar o texto do **termo de uso** com jurídico.
