-- =====================================================================
-- Fechaí — Caixinha: rendimento pode ser NEGATIVO (perda/prejuízo)
-- =====================================================================
-- "Rendeu negativo" (investimento) ou "emprestou e perdeu" (calote) baixam o
-- valor da unidade e encolhem o saldo de todos proporcional à participação.
-- Antes o rendimento só aceitava valor > 0; agora aceita ≠ 0.
-- =====================================================================

alter table caixinha_earnings drop constraint if exists caixinha_earnings_amount_check;
alter table caixinha_earnings add constraint caixinha_earnings_amount_check check (amount <> 0);
