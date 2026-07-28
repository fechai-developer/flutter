-- =====================================================================
-- Fechaí — Caixinha: ajuste manual de saldo (correção pelo dono)
-- =====================================================================
-- O dono corrige o saldo de um participante; [delta] (com sinal) muda o saldo
-- da pessoa e o patrimônio no mesmo valor. Aparece no histórico como "Ajuste
-- manual". Não tem check de sinal — pode ser negativo.
-- =====================================================================

create table if not exists caixinha_adjustments (
  id           uuid primary key default gen_random_uuid(),
  caixinha_id  uuid not null references caixinhas(id) on delete cascade,
  member_id    uuid not null references caixinha_members(id) on delete cascade,
  delta        numeric(12,2) not null,
  note         text,
  date         timestamptz not null default now()
);

alter table caixinha_adjustments enable row level security;

drop policy if exists "cxa read" on caixinha_adjustments;
create policy "cxa read" on caixinha_adjustments
  for select using (public.caixinha_can_see_all(caixinha_id));
-- Escrita restrita ao DONO (ajuste é prerrogativa dele, não de tesoureiro).
drop policy if exists "cxa write" on caixinha_adjustments;
create policy "cxa write" on caixinha_adjustments
  for all using (public.is_caixinha_owner(caixinha_id)) with check (public.is_caixinha_owner(caixinha_id));

-- Realtime
do $$
begin
  execute 'alter table public.caixinha_adjustments replica identity full';
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'caixinha_adjustments'
  ) then
    execute 'alter publication supabase_realtime add table public.caixinha_adjustments';
  end if;
end $$;
