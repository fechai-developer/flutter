-- =====================================================================
-- Fechaí — Caixinha: cotas por participante + saída de participante
-- =====================================================================
-- 1) quantas cotas cada participante tem (multiplica o aporte sugerido).
-- 2) saída: o participante recebe de volta SÓ o que aportou (sem rendimento);
--    o lucro que ele deixaria fica para quem permanece. Fica no histórico.
-- =====================================================================

alter table caixinha_members
  add column if not exists quotas int not null default 1 check (quotas >= 1);

create table if not exists caixinha_exits (
  id           uuid primary key default gen_random_uuid(),
  caixinha_id  uuid not null references caixinhas(id) on delete cascade,
  member_id    uuid not null references caixinha_members(id) on delete cascade,
  refund       numeric(12,2) not null check (refund >= 0),
  date         timestamptz not null default now()
);

alter table caixinha_exits enable row level security;

-- Quem participa vê as saídas; o próprio que saiu também vê a sua.
drop policy if exists "cxx read" on caixinha_exits;
create policy "cxx read" on caixinha_exits
  for select using (
    public.caixinha_can_see_all(caixinha_id)
    or exists(select 1 from caixinha_members m where m.id = member_id and m.profile_id = auth.uid())
  );
drop policy if exists "cxx write" on caixinha_exits;
create policy "cxx write" on caixinha_exits
  for all using (public.is_caixinha_treasurer(caixinha_id)) with check (public.is_caixinha_treasurer(caixinha_id));

-- Realtime
do $$
begin
  execute 'alter table public.caixinha_exits replica identity full';
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'caixinha_exits'
  ) then
    execute 'alter publication supabase_realtime add table public.caixinha_exits';
  end if;
end $$;
