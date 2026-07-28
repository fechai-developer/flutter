-- =====================================================================
-- Fechaí — Caixinha: período (início da 1ª parcela e fim opcional)
-- =====================================================================
alter table caixinhas
  add column if not exists start_date date,
  add column if not exists end_date   date;
