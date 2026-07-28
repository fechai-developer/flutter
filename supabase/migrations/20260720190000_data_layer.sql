-- Complementos para a camada de dados do app (acertos + juros de atraso).

-- Coluna de meses em atraso na cota (para acréscimo de juros, #2).
alter table subscription_members
  add column if not exists months_late int not null default 0;

-- Acertos de conta ("Já paguei" / "Já recebi", #4/#5).
create table if not exists payments (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references groups(id) on delete cascade,
  from_member  uuid not null references group_members(id) on delete cascade,
  to_member    uuid not null references group_members(id) on delete cascade,
  amount       numeric(12,2) not null check (amount > 0),
  created_at   timestamptz not null default now()
);

alter table payments enable row level security;

-- Membros do grupo leem os acertos.
drop policy if exists "pay read" on payments;
create policy "pay read" on payments
  for select using (public.is_group_member(group_id));

-- Só as 2 pessoas envolvidas (de/para) podem registrar o acerto (#6).
drop policy if exists "pay insert involved" on payments;
create policy "pay insert involved" on payments
  for insert with check (
    public.is_group_member(group_id)
    and exists (
      select 1 from group_members gm
      where gm.id in (from_member, to_member) and gm.profile_id = auth.uid()
    )
  );
