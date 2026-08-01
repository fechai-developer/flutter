-- =====================================================================
-- Fechaí — Guardar o rateio DIGITADO na despesa
-- =====================================================================
-- `expense_shares.share` guarda o resultado em dinheiro, e esse resultado é
-- irreversível: 3:2:1 de R$ 100 vira 50,00 / 33,33 / 16,67, e o arredondamento
-- em centavos come a razão original. Ao reabrir a despesa para editar, a tela
-- tentava reconstruir as partes a partir do dinheiro e mostrava números sem
-- sentido (5000, 3333, 1667) em vez de "3x, 2x, 1x".
--
-- A correção é guardar o que a pessoa digitou, ao lado do valor calculado:
--   - partes  → 3, 2, 1
--   - %       → 50, 30, 20
--   - exato   → o próprio valor
--   - igual   → nada (não há entrada do usuário)
--
-- Nulo = despesa antiga, salva antes desta coluna. Para essas, a tela continua
-- derivando das cotas (com uma redução de razão melhor); ao salvar de novo, a
-- despesa passa a ter o valor digitado gravado.
--
-- 4 casas decimais: porcentagem quebrada (33,3333%) precisa de mais precisão
-- que os 2 dígitos do dinheiro.
-- =====================================================================

alter table expense_shares
  add column if not exists split_input numeric(14,4);

comment on column expense_shares.split_input is
  'O que o usuário digitou no rateio (partes/%/valor), conforme expenses.split_type. Null = divisão igual ou despesa anterior a esta coluna.';
