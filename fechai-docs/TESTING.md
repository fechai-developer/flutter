# Testar com dados reais (Supabase)

Login de teste por **e-mail + senha** (sem depender de inbox). Padrão fácil de lembrar.

## 1. Criar os usuários de teste (uma vez, no painel)
Supabase → **Authentication → Users → Add user**. Marque **"Auto Confirm User"**. Crie:

| E-mail | Senha | Papel |
|---|---|---|
| `voce@fechai.test`  | `Fechai123!` | Conta principal (você) |
| `ana@fechai.test`   | `Fechai123!` | Colega de grupo |
| `bruno@fechai.test` | `Fechai123!` | Colega (com cota em atraso) |

> Mesma senha nos três só para facilitar o teste. Em produção isso não existe.

## 2. Popular dados de exemplo (uma vez, depois de criar os usuários)
Supabase → **SQL Editor** → cole o conteúdo de [`supabase/seed_test.sql`](../supabase/seed_test.sql) → **Run**.
Cria o grupo "Praia de Maresias" (com despesas divididas) e a assinatura "Netflix" (Bruno em atraso, com juros). É idempotente: rodar de novo não duplica.

> O perfil da `voce@fechai.test` fica **sem chave PIX de propósito**, para você ver a tela de **completar perfil** no primeiro login.

## 3. Rodar o app com backend ligado
```bash
flutter run -d chrome --dart-define=USE_SUPABASE=true
```
- Entre com `voce@fechai.test` / `Fechai123!`.
- Aceite o termo → complete o perfil (nome + chave PIX) → veja os dados reais.
- Faça login também como `ana@fechai.test` (em outra janela/anônima) para ver o **mesmo grupo pelo outro lado** — bom para validar privacidade/RLS.

## O que validar
- Criar/editar grupo e despesas → conferir no **Table Editor** (`groups`, `expenses`, `expense_shares`).
- "Já paguei"/"Já recebi" → aparece em `payments` e o saldo zera.
- Cobrar / juros de atraso do Bruno.
- **Privacidade:** logado como Ana, você **não** deve ver dados de grupos/assinaturas dos quais ela não participa.

## Voltar para o modo mock (offline, sem login)
```bash
flutter run                       # ou --dart-define=USE_SUPABASE=false
```
