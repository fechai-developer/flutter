-- =====================================================================
-- Fechaí — Caixinha: juros de cota CRISTALIZADOS
-- =====================================================================
-- Problema que esta tabela resolve
-- --------------------------------
-- O juro de atraso de cota é DERIVADO no cliente: para cada mês vencido sem
-- aporte, o juro compõe sobre (principal + juros). Consequência indesejada: ao
-- registrar o aporte de um mês vencido (datado no próprio mês, para a
-- participação daquele mês ficar correta), o mês sai do atraso e o juro que ele
-- vinha gerando SUMIA — mesmo que a pessoa tenha pago só a cota, sem os juros.
--
-- Solução: quando a cota de um mês vencido é paga mas o juro dela não, esse
-- juro é "cristalizado" aqui — vira dívida registrada do participante, que
-- continua no radar até ser paga. Ao ser paga, vira rendimento da caixinha
-- (caixinha_earnings, source = 'loanInterest'), como qualquer juro.
--
-- Invariante garantido pelo cliente (test/caixinha_test.dart, grupo "Quitação
-- parcial"): a dívida total cai EXATAMENTE o valor pago — nada de juro
-- perdido nem cobrado em dobro.
--
-- [amount]      juro devido cristalizado.
-- [paid_amount] quanto dele já foi pago (quitação parcial é permitida).
-- Não volta a compor juros: já foi composto até a cristalização (decisão de
-- projeto para grupo informal — ver fechai-docs/CAIXINHA.md).
-- =====================================================================

create table if not exists caixinha_cota_charges (
  id           uuid primary key default gen_random_uuid(),
  caixinha_id  uuid not null references caixinhas(id) on delete cascade,
  member_id    uuid not null references caixinha_members(id) on delete cascade,
  amount       numeric(12,2) not null check (amount > 0),
  paid_amount  numeric(12,2) not null default 0 check (paid_amount >= 0),
  note         text,
  date         timestamptz not null default now(),
  recorded_by  uuid references profiles(id) on delete set null default auth.uid(),
  constraint caixinha_cota_charges_paid_within_amount check (paid_amount <= amount)
);

create index if not exists caixinha_cota_charges_caixinha_idx
  on caixinha_cota_charges (caixinha_id);

alter table caixinha_cota_charges enable row level security;

-- Leitura: quem participa da poupança (borrower NÃO vê), igual a aportes/rendimentos.
drop policy if exists "cxcc read" on caixinha_cota_charges;
create policy "cxcc read" on caixinha_cota_charges
  for select using (public.caixinha_can_see_all(caixinha_id));

-- Escrita: dono e tesoureiros (mesma regra de aporte/rendimento/empréstimo).
drop policy if exists "cxcc write" on caixinha_cota_charges;
create policy "cxcc write" on caixinha_cota_charges
  for all using (public.is_caixinha_treasurer(caixinha_id))
  with check (public.is_caixinha_treasurer(caixinha_id));

-- Realtime (sinal de invalidação; a RLS acima já filtra por usuário).
do $$
begin
  execute 'alter table public.caixinha_cota_charges replica identity full';
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'caixinha_cota_charges'
  ) then
    execute 'alter publication supabase_realtime add table public.caixinha_cota_charges';
  end if;
end $$;
