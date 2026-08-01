-- =====================================================================
-- Fechaí — Caixinha: contexto do aporte no histórico
-- =====================================================================
-- Antes, todo aporte aparecia no Histórico como "Aporte", mesmo quando veio
-- de uma quitação de atraso (settleCotaArrears) — perdendo o contexto de que
-- foi uma quitação parcial (ex.: pagou a cota mas manteve os juros devidos).
--
-- [note] é opcional: null = aporte comum ("Registrar"/FAB "Aporte"), rótulo
-- padrão "Aporte" no histórico. Preenchido só quando o aporte nasce de outro
-- fluxo (hoje: "Quitação de atraso").
-- =====================================================================

alter table caixinha_contributions add column if not exists note text;
