# Fechaí — contexto do projeto

App brasileiro que junta divisão de despesas de grupo/evento (estilo Splitwise) com divisão de assinaturas recorrentes (Netflix, Spotify, Microsoft 365 etc.), cobrança via WhatsApp ("Cobra Aí") e PIX copia-e-cola nativo. Documentação completa em `PRD.md`.

## Antes de começar a codar

Leia, nesta ordem:
1. `PRD.md` — escopo do MVP (seção 5), o que fica de fora por enquanto (seção 6), modelo de negócio (seção 7)
2. `DESIGN_SYSTEM.md` — paleta, tipografia, motion
3. `app_theme.dart` — implementação do tema, copiar para `lib/theme/app_theme.dart` no projeto novo

## Stack definida

- **Flutter** (web + iOS + Android no mesmo código-base) — não sugerir React/outra stack, já foi decidido.
- **Gerenciamento de estado: Riverpod** (decidido na sessão de setup). Providers em `lib/data/repositories/providers.dart`; mutações via `RepositoryController` que invalida os `FutureProvider` de leitura.
- **Backend: Supabase** (decidido e integrado). Migrações versionadas em `supabase/migrations/` (aplicar com `supabase db push`). `AppRepository` tem duas implementações: `InMemoryRepository` (mock, dev/offline) e `SupabaseRepository` (real, já escrito). `appRepositoryProvider` escolhe automaticamente conforme login + flag `USE_SUPABASE`. A UI não muda entre os dois.

## Estado atual e próximos passos (LER AO RETOMAR)

- Fonte da verdade do roadmap: **`IMPLEMENTATION_TODO.md`**. Como testar dados reais: **`TESTING.md`**.
- **Feito:** Etapa 1 (mock) e Etapa 2 (Supabase) — ambas **validadas em runtime pelo usuário**. **Etapa C — Convite/Social** feita (status por membro `MemberStatus`, aceitar/recusar, nome entre aspas + tag Pendente/Recusado, convite WhatsApp; validada no mock). Falta rodar a Etapa C no Supabase real e aplicar a migração `20260721160000_declined_status.sql`.
- **Etapa S — Segurança: backbone no banco FEITO** (migrações `20260721170000`..`20260721210000`, aplicadas exceto `200000`/`210000` que são as últimas): self-accept (só o próprio membro aceita vínculo — fecha vazamento de nome+PIX), teto de juros ≤20%/mês, **freemium imposto no servidor** (`plan_limits` + triggers; limite conta só grupos/assinaturas **ativos** via `archived_at`), fonte do premium = `profiles.plan` (só service_role), LGPD (`delete_my_account` anonimiza / `export_my_data` / termo versionado), rate limit anti-enumeração. **Freemium na UI FEITO**: RPC `my_plan_status()` → `PlanStatus`/`planStatusProvider`; juros travado + banner de limite + folha `PremiumUpsell` (`lib/core/widgets/premium.dart`); card de plano no perfil. **Falta:** aplicar `200000`/`210000`, auditar RLS com 2 usuários, disclaimers/UI de conta (excluir/exportar), arquivar grupo/assinatura, upsell na tela Cobrar, checkout real do premium. Detalhe em `IMPLEMENTATION_TODO.md` → Etapa S.
- **Etapa D — Saldos consolidados & refino de UX FEITO** (validado no mock): tela **Acertar** (substitui "Cobrar") consolida **pessoa a pessoa** grupos + assinaturas e **quita de uma vez** (`ConsolidatedBalances` + `settle_screen.dart`); FAB "Cobrar tudo"; nav reordenada (Acertar após Início, ícone dinheiro); Cobrar/Pagar com **PIX de cara + QR/mensagem em gavetas** (`ExpandableTile`/`PixQr`); **participantes** visíveis (`ParticipantsStrip` + avatares); **despesa recorrente com dia (1–27)** (migração `20260721180000`); **tema claro moderno** (nomes só negrito); atividade recente paginada. Detalhe em `IMPLEMENTATION_TODO.md` → Etapa D.
- **Nome + Sobrenome & polimento de UX FEITO** (sessão 2026-07-22, migração `20260721220000_last_name.sql` aplicada): `Person.name` = **primeiro nome** + novo `lastName` (getters `fullName`/`initials`); avatares com **2 iniciais** (`MemberAvatar.person`). **Nome real após o aceite** via gatilhos `stamp_real_name`/`propagate_profile_name` (fecha o pendente da Etapa C; `payee_info` agora traz `last_name`). Listas de participantes mostram nome completo (aspas até aceitar); feed/cards seguem primeiro nome. Campos Nome+Sobrenome em todos os formulários + edição de nome no Perfil. **X para fechar** os bottom sheets (`core/widgets/sheet_handle.dart`). **Bug corrigido:** editar despesa por %/partes não salvava (inputs não eram repreenchidos). Detalhe no `IMPLEMENTATION_TODO.md`.
- **Caixinha — poupança coletiva FEITA** (sessão 2026-07-22): terceira frente, além de Contas e Assinaturas. Aportes mensais + **partilha por participação (unidade × tempo)**; **empréstimos** a juros combinados com **quitação parcial** (juros sobre saldo devedor); **rendimentos** (banco + juros); **papéis** (dono/tesoureiro/membro/**externo** — este só vê o próprio empréstimo, sem aceite); **saída** de participante (devolve só o aportado, lucro fica pra quem continua); **cotas por participante**; **período** (início/fim); **projeção** estimada + **relatório PDF** (`pdf`/`printing`). Modelo `lib/data/models/caixinha.dart` (lógica nos getters), feature em `lib/features/caixinha/`, 5ª aba + rota `/caixinhas`. Migrações **aplicadas**: `20260722130000_caixinha.sql` (tabelas + RLS por papel + realtime), `20260722160000_caixinha_exits.sql` (saídas + `quotas`), `20260722170000_caixinha_period.sql` (datas). Matemática validada por invariantes em `test/caixinha_test.dart` (cenário complexo). **Falta:** smoke test E2E no Supabase real e **gating freemium** (a decidir — juros do empréstimo NÃO é premium, é core).
- **Remoção de membro com preservação de histórico FEITA** (sessão 2026-07-22, migrações `20260722120000_member_removal`/`20260722140000_recurrence_review` aplicadas): só remove quem está **zerado** (RPCs `remove_group_member`/`remove_subscription_member` autorizam dono **ou o próprio** = auto-saída); **sem histórico → some** (hard delete), **com histórico → soft** (`removed_at`) mantendo acesso **somente-leitura** ao próprio histórico. RLS: `is_group_member`/`is_sub_member` contam **só ativos**, `was_*`/`involved_in_expense` devolvem acesso pontual. UI: **"Arquivado"** nas listas + detalhe só-leitura + **"Ex-participantes"** + **"Sair"**. Detalhe no `IMPLEMENTATION_TODO.md`.
- **Geração de recorrência FEITA (Fase E, item 1)** (sessão 2026-07-22): função SQL idempotente `generate_due_recurrences` (migrações `20260722180000` + `20260722190000` "mês corrente") + gerador Dart `lib/core/utils/recurrence.dart`. Gera **só o mês corrente** quando vence (sem backfill), **exclui quem saiu e redivide proporcional**, **bloqueia** se o pagador saiu (`payerLeft`). **100% via pg_cron** (job `gerar-recorrencias` agendado; sem botão). Cobrança automática (D+3/D+10/D+30) e conciliação PIX seguem fora (itens 2/3 da Fase E).
- **Ordem a fazer:** ~~Convite/Social~~ → **Segurança (em andamento)** → Ligar login/produção. **Cobrança automática** foi movida para **Fase E — enhancements pós-deploy** (não bloqueia lançamento).
- Login por e-mail é o padrão; OTP/WhatsApp fica para a fase final. `USE_SUPABASE` default `false` (roda mock) durante o dev.
- Navegação: `go_router` com `StatefulShellRoute` (4 abas). Deep links usam hash strategy (padrão Flutter web).
- Pacotes já mapeados no PRD (seção 8): `url_launcher`, `qr_flutter`, `google_fonts` (usados). `firebase_auth` substituído por Supabase Auth. Ícones: ver nota em `DESIGN_SYSTEM.md` (phosphor bloqueado no Flutter 3.44 → `lib/core/icons.dart`).

## Estrutura do projeto (implementado no setup)

```
lib/
  main.dart                      # ProviderScope + MaterialApp.router + init intl pt-BR
  theme/app_theme.dart           # cópia do doc (AppTheme/AppColors)
  core/
    icons.dart                   # AppIcons/AppIconsFill (Material como base do phosphor)
    router/app_router.dart       # go_router + shell de 4 abas
    utils/  currency.dart pix.dart whatsapp.dart balance.dart
    widgets/ wave_clipper.dart wave_card.dart money_text.dart member_avatar.dart
  data/
    models/  person expense expense_group subscription caixinha
    repositories/ app_repository (interface) in_memory_repository supabase_repository providers
    realtime/ realtime_sync (Supabase Realtime como sinal de invalidação)
  features/
    auth/ home/ groups/ subscriptions/ charge/ caixinha/ profile/ shell/
supabase/migrations/             # migrações versionadas (schema + RLS + funções); schema.sql é só ponteiro
supabase/seed_test.sql           # dados de teste (rodar no SQL Editor após criar usuários)
```
> A estrutura cresceu além do setup: `core/widgets` tem status_chip, filter_bar, pending_badge, user_name, brand_mark, interest_slider, pix_key_field, emoji_picker, etc.; `features` inclui `stats/` (Resumo). Ver o código para o estado atual.

Rodar: `flutter run` (mock) ou `flutter run --dart-define=USE_SUPABASE=true` (real). Testes: `flutter test`.

**Novidade sobre o PRD**: as 5 abas são **Início · Acertar · Contas · Assinaturas · Caixinha** (a Caixinha — poupança coletiva — é a 3ª frente, feita em 2026-07-22). A aba **"Contas"** (rótulo de UI; o domínio interno segue `ExpenseGroup`/`groups`) é a antiga "Grupos" de despesas de evento. A aba **"Acertar"** (era "Cobrar") consolida os saldos **pessoa a pessoa**, somando grupos + assinaturas, e permite **quitar tudo com alguém de uma vez** (registra o acerto em cada grupo + marca as cotas). Cobrar ("Cobra Aí", que serve a North Star) e Pagar são **ações dentro** dessa tela; há FAB "Cobrar tudo". Também acessível tocando no card de saldo da Home. Decidido nas sessões de UX — atualizar PRD seção 5 se for oficializar.

## Escopo do MVP — não expandir sem confirmar

As duas frentes juntas desde o início:
- Cadastro por celular (OTP)
- Grupos de despesas (evento): lançar gasto, dividir igual/%/customizado, saldo consolidado
- Assinaturas compartilhadas: cadastro de serviço, cotas automáticas, recorrência mensal, juros configuráveis por atraso
- "Cobra Aí": mensagem pré-formatada + link WhatsApp (`wa.me`) + PIX copia-e-cola
- Marcar pagamento como recebido é manual no MVP — **não implementar conciliação automática de PIX agora**, é v2 (ver PRD seção 6)

## Regras de negócio a não esquecer

- App **não custodia dinheiro** — não é um PSP, só orquestra a comunicação de cobrança. Não desenhar fluxo que faça o app "segurar" saldo do usuário.
- Juros configuráveis por atraso precisam de teto sugerido/aviso — **teto rígido de 20%/mês no banco** (check) + gating premium (só premium liga juros>0); UI mostra slider travado no free.
- Nunca usar "Pix" como parte de nome de produto/marca — é marca do Banco Central
- Modelo freemium: **imposto no servidor** via `plan_limits` + triggers (não gatear só no cliente). Limites contam **ativos** (`archived_at is null`). UI lê `my_plan_status()` / `is_premium()`. Ver PRD seção 7 e `IMPLEMENTATION_TODO.md` → Etapa S.

## Convenções de código

- Cores, tipografia e espaçamento sempre via `AppTheme`/`AppColors` de `app_theme.dart` — nunca hardcodar hex ou `TextStyle` solto
- Valores monetários sempre com `AppTheme.moneyStyle()`, nunca com o `TextTheme` padrão
- Corte de onda nos cards de saldo/cobrança é o elemento de assinatura visual do produto — não trocar por card retangular padrão sem discutir

## Concorrência (contexto, não copiar features 1:1)

Rachaí, Ratio e Racha aí cobrem só a parte de grupo/evento. Splitfee e Kotas só assinatura. NG.ZAP (dentro do banco NG.CASH) já faz cobrança PIX via WhatsApp. Nosso diferencial é juntar tudo com juros configuráveis — é isso que vale proteger na hora de priorizar o que entra no MVP.
