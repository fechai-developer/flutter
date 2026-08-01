# Caixinha — como funciona

Documento de referência do fluxo da Caixinha: o que cada tela faz, como o
dinheiro é contabilizado, **como os juros são aplicados** e quais testes
garantem que a conta fecha.

> **Enquadramento:** o Fechaí organiza finanças entre pessoas de confiança. Não é
> instituição financeira: não empresta, não cobra e não guarda dinheiro. Valores
> e taxas são combinados entre os participantes.

---

## 1. Conceitos

| Conceito | O que é |
|---|---|
| **Cota** | Quanto cada participante coloca por mês (`monthly_quota`). Quem tem N cotas paga N × valor. |
| **Dia de vencimento** | Dia do mês em que a cota vence (`payment_day`). **Obrigatório na criação.** A partir dele a cota não paga vira atraso com juros. |
| **Patrimônio** | Tudo aportado + tudo rendido + ajustes − devoluções de saída. |
| **Em caixa** | Patrimônio − o que está emprestado. |
| **Participação** | Fatia de cada um no patrimônio, por **unidade × tempo** (ver §3). |
| **Rendimento** | Dinheiro que entrou sem ser aporte: banco/poupança ou juros. Sobe o patrimônio de todos. |

### Papéis

| Papel | Vê | Lança |
|---|---|---|
| **Dono** | tudo | tudo + elege tesoureiros, ajusta saldo, encerra, exclui |
| **Tesoureiro** | tudo | aporte, rendimento, empréstimo, quitação |
| **Membro** | tudo (grupo de confiança: vê cotas e atrasos de todos) | nada |
| **Tomador externo** (*borrower*) | só o nome da caixinha e o **próprio** empréstimo | nada |

Isso é imposto **no cliente e no servidor** (RLS do Postgres) — ver §7.

---

## 2. As abas da caixinha

### Início
Patrimônio, sua parte, *em caixa / emprestado / rendeu*, gráfico de evolução
(real + projeção tracejada, com tooltip por mês), botões de Projeção e
Relatório (PDF), e a partilha quando encerrada.

### Quitação
Cotas **mês a mês** (navega do início da caixinha até o fim/mês atual) com o
status de cada participante, e a seção **"Quitações em atraso"** (só
dono/tesoureiro, recolhível, com badge de quantas pessoas devem).

Dois caminhos, propositalmente distintos:

| Ação | Onde | O que faz | Juros |
|---|---|---|---|
| **Registrar** (por mês) | linha do mês | Lança um aporte com **valor e data na mão** na competência daquele mês | **Não cobra** |
| **Quitar** (por pessoa) | seção Quitações | Abate a dívida a partir de um **valor** | **Cobra** (ou perdoa, no modo "Pagou em dia") |

### Empréstimos
Registro dos valores emprestados (a membros ou a gente de fora), com juros do
mês, pagamentos e "marcar como perda".

### Histórico
Extrato completo: **o que foi lançado, para quem, por quem, o valor e o
patrimônio antes → depois**. Cobre aportes, rendimentos, ajustes e saídas.

### Botão flutuante "Lançar"
Só para dono/tesoureiro: **Aporte**, **Rendimento**, **Emprestar**.

---

## 3. Participação: unidade × tempo

Cada aporte "compra" unidades pelo valor da unidade **no momento** (começa em
R$ 1,00). Rendimento **não** cria unidades — valoriza as existentes. Logo, quem
entrou antes acumula mais.

A competência é **mensal**: quem pagou dia 1 ou dia 28 do mesmo mês entra igual
no rendimento daquele mês. Dentro do mês a ordem é *aporte → rendimento → saída*.

**Saída:** quem sai leva **só o que aportou** (sem lucro); o lucro que ele deixa
é diluído entre quem fica.

---

## 4. Aplicação de juros

### 4.1 Empréstimos
- Juros são **lançados explicitamente** ("Juros do mês") sobre o **saldo devedor**
  (principal + juros já lançados − pago) → compostos.
- Empréstimo com **data no passado** gera juros retroativos automáticos: um
  lançamento cheio (taxa × principal) por mês decorrido.
- O juro lançado vira **rendimento da caixinha**, dividido entre todos.
- **Pagamento parcial não apaga juros** — eles já estão registrados.
- Calote: "Marcar como perda" lança rendimento **negativo** do saldo devedor.

### 4.2 Cotas em atraso — o modelo justo

Para cada mês vencido sem aporte, o juro **compõe** ao mês sobre
(principal + juros). Exemplo com cota R$ 100 e 10% a.m.:

| mês | juro do mês | principal acum. | juros acum. |
|---|---|---|---|
| jan | — (1º) | 100 | 0 |
| fev | 10% × 100 = 10,00 | 200 | 10,00 |
| mar | 10% × 210 = 21,00 | 300 | 31,00 |
| abr | 10% × 331 = 33,10 | 400 | **64,10** |

#### O problema que existia
O juro é **derivado** dos aportes por mês. Ao registrar o aporte de um mês
vencido (datado no próprio mês, para a participação daquele mês ficar correta),
o mês saía do atraso e **o juro dele sumia** — mesmo que a pessoa tivesse pago só
a cota, sem os juros.

#### A solução: juro cristalizado
Quando a cota de um mês vencido é paga **sem** os juros, esse juro é
**cristalizado**: vira uma dívida registrada (`caixinha_cota_charges`) que
continua no radar até ser paga. Ao ser paga, vira rendimento da caixinha.

Assim: **juros devidos = juros ainda deriváveis dos meses em aberto + juros
cristalizados.**

#### Como a quitação aloca o valor
1. **Principal**, dos meses **mais antigos → mais novos**. O que sobrar fica de
   parcial na cota seguinte (a cota **continua em aberto** com o saldo menor).
2. **Juros**: primeiro os já cristalizados (mais antigos), depois os que
   acabaram de ser liberados.
3. O juro liberado que **não** foi pago é cristalizado.

> **Invariante garantido por teste:** a dívida total cai **exatamente** o valor
> pago. Nada de juro perdido nem cobrado em dobro.

**Exemplo** (4 meses vencidos, dívida R$ 464,10 — R$ 400 de cotas + R$ 64,10 de
juros). A pessoa paga **R$ 100**:
- Quita a cota de janeiro (R$ 100).
- O juro que janeiro gerava (R$ 33,10) deixaria de existir → é **cristalizado**.
- Dívida depois: R$ 300 de cotas + R$ 31,00 derivado + R$ 33,10 cristalizado
  = **R$ 364,10** — exatamente R$ 100 a menos. ✅

#### Modo "Pagou em dia"
Correção de registro (reconstrução do histórico): lança os aportes datados nos
meses e **perdoa** os juros deles — porque não houve atraso de verdade. Juros já
cristalizados **continuam devidos** nos dois modos.

#### Decisão de projeto
O juro cristalizado **não volta a compor** juros (já foi composto até a
cristalização). É a escolha conservadora, adequada a um grupo informal. Mudar
isso é localizado: `Caixinha.carriedInterestOf` + `cotaArrearsOf`.

---

## 5. Caixinha "já em andamento" (migração do caderno)

Na criação existem dois modos:

- **Começar do zero** — começa hoje; nem pede data de início.
- **Já em andamento** — pede *quando começou* (pode ser no passado) e o
  **saldo atual** de cada um (atalho rápido: vira um aporte-semente).

Ao criar "já em andamento", a caixinha abre com o **guia de preenchimento**
(3 passos: revisar cotas → lançar rendimentos → registrar empréstimos). O guia
aparece **só na primeira vez**; depois é reaberto pelo menu **"Preencher
histórico"**.

Para reconstruir o passado sem cobrar juros indevidos, use **"Registrar"** na
linha de cada mês (valor + data reais) ou o modo **"Pagou em dia"** na quitação.

---

## 6. Modelo de dados

| Tabela | Guarda |
|---|---|
| `caixinhas` | nome, emoji, dono, juros padrão, cota, dia de vencimento, período, status |
| `caixinha_members` | participantes (papel, aceite, nº de cotas) |
| `caixinha_contributions` | aportes (valor, data, quem lançou) |
| `caixinha_earnings` | rendimentos — investimento ou juros (pode ser negativo = perda) |
| `caixinha_loans` / `caixinha_loan_payments` | empréstimos e pagamentos |
| `caixinha_exits` | saídas (devolução do aportado) |
| `caixinha_adjustments` | ajuste manual de saldo (só dono) |
| **`caixinha_cota_charges`** | **juros de cota cristalizados** (`amount`, `paid_amount`) |

A matemática de participação/juros roda **no cliente** (`lib/data/models/caixinha.dart`),
a partir desses eventos — o banco guarda fatos, não saldos.

---

## 7. Segurança (RLS)

- **Leitura**: só quem tem vínculo. `caixinha_can_see_all` (dono/tesoureiro/membro)
  vê aportes, rendimentos, membros, empréstimos e cobranças de juros.
  O *borrower* vê **apenas** o próprio empréstimo/pagamentos e o nome da caixinha.
- **Escrita**: `is_caixinha_treasurer` (dono + tesoureiros) para aportes,
  rendimentos, empréstimos e `caixinha_cota_charges`. **Ajuste de saldo: só o dono.**
- **Anti-escalada**: trigger `enforce_caixinha_self_accept` impede um membro de
  mudar o próprio papel (só o `invite_status`).
- Membro comum **vê** cotas/atrasos de todos (decisão de produto: grupo de
  confiança), mas **não escreve** — bloqueado no cliente e na RLS.

---

## 8. Testes

`flutter test` — **122 testes, todos passando**; `flutter analyze` sem erros.

### Matemática (`test/caixinha_test.dart`)
- Participação por unidade × tempo; quem entrou depois recebe menos.
- Soma das partes = patrimônio; participações somam 100%.
- Rendimento é mensal (dia do aporte não importa).
- Saída leva só o aportado; lucro fica para quem continua.
- Perdas: rendimento negativo e calote de empréstimo.
- Empréstimo: saldo = principal + juros − pago; quitação parcial e total.
- Juros retroativos de empréstimo datado no passado.
- Atraso de cota com juros compostos (jan/fev/mar conferidos à mão).
- Ajuste manual e histórico com saldo acumulado.
- Série do gráfico e projeção (inclusive até a data-fim).

### Quitação — "o juro devido nunca some" (`test/caixinha_test.dart`)
| Teste | Garante |
|---|---|
| cenário base | 4 meses vencidos = R$ 400 + R$ 64,10 de juros |
| pagar exatamente a cota mais antiga | juro **não** é apagado — vira cristalizado |
| **invariante da conservação** | para R$ 50/100/150/233,33/400: dívida cai **exatamente** o valor pago, e a prévia da tela bate com o resultado real |
| pagamento parcial de uma cota | o resto continua na própria cota |
| pagar tudo | zera a dívida, não cristaliza nada |
| "pagou em dia" | corrige o registro sem cobrar juros |
| juro cristalizado | é cobrado **antes** do novo e some ao ser pago |
| sem cota/vencimento | juro cristalizado continua devido |

### Tela (`test/caixinha_screen_test.dart`)
- Abre em abas (Início/Quitação/Empréstimos/Histórico) sem exceções.
- Dono vê "Lançar" com Aporte, Rendimento e Emprestar.
- **Membro comum NÃO vê "Lançar"** (permissão na UI).
- Aba Quitação lista convidado sem aceite, com **nome + sobrenome**.
- Aba Histórico mostra o extrato com **patrimônio antes → depois**.

### O que NÃO foi verificado
- **Conferência visual** (layout/cores): o Flutter Web renderiza em canvas e o
  painel do navegador não permitiu screenshot nesta sessão. A validação foi por
  teste de widget (estrutura e permissões), não por inspeção visual.
- A migração `20260729140000_caixinha_cota_charges.sql` **ainda não foi aplicada**
  ao Supabase — rodar `supabase db push` antes de usar a quitação em produção.

---

## 9. Pendências conhecidas

- [ ] `supabase db push` da migração de `caixinha_cota_charges`.
- [ ] Juro cristalizado não compõe (decisão consciente — revisar se o grupo quiser).
- [ ] O modo "já em andamento" com saldo-semente é uma *foto de hoje*; o histórico
      mês a mês só existe se for reconstruído pelo guia.

## 10. Edição travada após o 1º lançamento (sessão 2026-07-31)

O modelo **não versiona o passado** — `cotaArrearsOf` recalcula o atraso de
todos os meses a partir do `monthlyQuota`/`paymentDay`/`quotas` **atuais**, não
de um snapshot de cada mês. Por isso, mudar esses campos depois que já existe
aporte/rendimento/empréstimo/ajuste (`Caixinha.hasMovements`) reescreveria
retroativamente juros já cobrados ou perdoados.

Decisão de produto: **cota, dia de pagamento, data de início e cotas por
pessoa ficam travados assim que `hasMovements` é true** (`EditCaixinhaSheet` +
painel do membro). Data-fim continua editável sempre (só afeta a projeção, não
o passado). Versionar esses campos por período é o próximo passo se o grupo
precisar mudar cota/composição no meio do caminho sem esse travamento — não
implementado ainda.

**Excluir** segue o mesmo raciocínio: só permitido quando `!hasMovements`
(igual ao padrão de remoção de membro — hard delete só sem histórico). Com
lançamento, o único caminho é **Encerrar e partilhar**, que agora deixa a
caixinha **somente-leitura** (sem novo aporte/rendimento/empréstimo/edição;
Histórico/Relatório/empréstimos em aberto continuam visíveis) e mostra a
partilha **por pessoa** (antes só mostrava o valor de quem via a tela).

Histórico: lançamentos de quitação de atraso (`settleCotaArrears`) agora
carregam `Contribution.note = 'Quitação de atraso'` em vez de aparecerem como
"Aporte" genérico (migração `20260731120000_caixinha_contribution_note.sql`,
coluna `note` nullable — aplicar com `supabase db push`). A ordenação do
extrato usa desempate determinístico por índice original (evita embaralhar
lançamentos com a mesma data a cada rebuild).
