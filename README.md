# Fechaí

App brasileiro que junta **divisão de despesas de grupo/evento** (estilo Splitwise), **divisão de assinaturas recorrentes** (Netflix, Spotify, Microsoft 365…) e **caixinhas** (poupança coletiva da família/amigos com empréstimos a juros combinados), com cobrança via WhatsApp (**"Cobra Aí"**) e **PIX copia-e-cola** nativo.

Flutter (web + iOS + Android). Documentação de produto/design em [`fechai-docs/`](fechai-docs/) — comece por [`IMPLEMENTATION_TODO.md`](fechai-docs/IMPLEMENTATION_TODO.md) (estado atual e próximos passos) e [`TESTING.md`](fechai-docs/TESTING.md) (testar com dados reais).

## Rodar

```bash
flutter pub get
flutter run                                   # mock (padrão) — sem login, dados de exemplo
flutter run --dart-define=USE_SUPABASE=true   # backend real (login por e-mail+senha)
flutter test                                  # divisão, PIX/CRC16, juros, acerto de saldo, caixinha
```

Shell de 5 abas: **Início · Acertar · Contas · Assinaturas · Caixinha**. (Na UI, "Contas" é a antiga "Grupos" e "Acertar" é a antiga "Cobrar" — o domínio interno segue em inglês.)

## Estado atual
- **Etapas 1 e 2 (mock + Supabase):** completas e validadas em runtime.
- **Convite/Social, Saldos consolidados, Nome+Sobrenome, Remoção de membro:** feitos.
- **Caixinha (poupança coletiva):** feita — mock + Supabase, migrações aplicadas, matemática validada por testes; falta smoke test E2E e gating freemium (a decidir).
- **Próximo:** Segurança (em andamento) → Ligar login/produção. **Cobrança automática** virou *enhancement pós-deploy*. Detalhes no `IMPLEMENTATION_TODO.md`.

## Arquitetura (resumo)

- **Estado:** Riverpod (`lib/data/repositories/providers.dart`).
- **Dados:** interface `AppRepository` com duas implementações — `InMemoryRepository` (mock, dev/offline) e `SupabaseRepository` (backend real). `appRepositoryProvider` escolhe automaticamente: Supabase quando logado (`USE_SUPABASE=true`), mock caso contrário. A UI não muda.
- **Backend:** Supabase. Migrações versionadas em [`supabase/migrations/`](supabase/migrations/) (aplicar com `supabase db push`). Login por e-mail (senha nos testes; OTP/WhatsApp na fase final). Privacidade via RLS + função `payee_info`.
- **Navegação:** `go_router` + `StatefulShellRoute` (hash strategy no web).
- **Design system:** tema em `lib/theme/app_theme.dart`; corte de onda (assinatura visual) em `lib/core/widgets/wave_card.dart`; marca onda+R$ em `brand_mark.dart`; ícones em `lib/core/icons.dart` (Phosphor está bloqueado no Flutter 3.44 — ver `DESIGN_SYSTEM.md`).

## Funcionalidades implementadas

| Módulo | O que tem |
|---|---|
| **Login/Perfil** | E-mail + senha (mock ou Supabase); completar perfil no 1º acesso (**nome + sobrenome**/telefone/PIX) e **editar nome** no perfil; avatares com **2 iniciais** (nome+sobrenome); termo de uso; chave PIX com tipo, máscara e validação |
| **Início** | Saldo consolidado (gradiente + corte de onda), atalhos, pendências de assinatura, **feed de atividade** (crédito/débito), Resumo (gráfico pago x recebido/mês) |
| **Contas** (ex-Grupos) | Lista com **busca + filtros** (pessoa/status), **tags de status** e ordenação; criar/**editar**/**excluir**; **saldos simplificados** (quem paga quem); despesa com **divisão igual/%/partes/valor** + **recorrente**; **editar/excluir despesa**; **acerto** ("Já paguei"/"Já recebi") |
| **Assinaturas** | Lista com busca/filtros/tags; criar/**editar**; cotas por participante, status e **juros que acrescem no atraso**; adicionar participante |
| **Caixinha** | Poupança coletiva: aportes mensais, **partilha por participação (unidade × tempo)**, **empréstimos** a juros combinados com **quitação parcial**, **rendimentos** (banco + juros), **papéis** (dono/tesoureiro/membro/externo), **saída** (devolve só o aportado), **cotas por participante**, **período** (início/fim), **projeção** estimada e **relatório PDF** |
| **Acertar** (ex-Cobrar) | Consolida **pessoa a pessoa** (contas + assinaturas), **quita tudo de uma vez**, FAB "Cobrar tudo"; Cobra Aí/Pagar são ações dentro dela |
| **Cobra Aí / Pagar** | Folha com **PIX copia-e-cola (EMV/BR Code + CRC16)** + QR + mensagem WhatsApp (`wa.me`); "Pagar" mostra o PIX do recebedor; confirmar pagamento em destaque |

## Regras de negócio respeitadas

- O app **não custodia dinheiro** (não é PSP) — só orquestra a comunicação da cobrança.
- Juros por atraso são **ilustrativos** (até 20%, aviso acima de 1%), definidos entre as pessoas; reforçado no termo de uso.
- Marcar pagamento como recebido é **manual**; conciliação automática de PIX é enhancement futuro.
- Privacidade: dados de terceiros (**nome + sobrenome** + chave PIX) só aparecem com **vínculo aceito** (RLS + `payee_info`). Antes do aceite, mostra-se só o nome *sugerido* por quem convidou, entre "aspas"; após o aceite, o nome real do perfil substitui o sugerido (gatilhos no banco).
