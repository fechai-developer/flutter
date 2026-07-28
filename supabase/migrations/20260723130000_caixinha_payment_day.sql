-- =====================================================================
-- Fechaí — Caixinha: dia de pagamento (aniversário mensal)
-- =====================================================================
-- Define em que dia do mês a cota de cada participante vence. A partir do
-- aniversário, a cota não paga passa a acumular juros (como um empréstimo) —
-- a matemática do atraso é derivada no cliente a partir deste dia, do valor da
-- cota e da taxa de juros padrão da caixinha.
-- =====================================================================

alter table caixinhas
  add column if not exists payment_day int check (payment_day between 1 and 31);
