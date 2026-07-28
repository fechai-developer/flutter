-- =====================================================================
-- Fechaí — Caixinha (poupança coletiva + empréstimos a juros)
-- =====================================================================
-- Modelo: vários membros aportam; o dinheiro rende (banco + juros de
-- empréstimo); no fim partilha-se por participação (unidade × tempo, calculada
-- no cliente a partir dos aportes+rendimentos).
--
-- Papéis (caixinha_members.role):
--   owner     — criador; vê e edita tudo; elege tesoureiros; encerra.
--   treasurer — eleito; vê e edita (lança aporte/rendimento/empréstimo).
--   member    — contribui e acompanha.
--   borrower  — tomador EXTERNO; só pegou empréstimo. Sem aceite. Visão
--               restrita: enxerga só o próprio empréstimo + histórico, e o
--               nome da caixinha — nunca os aportes/saldos dos outros.
--
-- Privacidade: a RLS abaixo faz o borrower ver apenas as próprias linhas de
-- empréstimo/pagamento e o próprio cadastro; contribuições e rendimentos ficam
-- restritos a quem participa da poupança (owner/treasurer/member).
-- =====================================================================

-- ---------- Tabelas ----------
create table if not exists caixinhas (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  emoji                 text not null default '🐷',
  owner_id              uuid not null references profiles(id) on delete cascade,
  default_interest_pct  numeric(5,2) not null default 0 check (default_interest_pct >= 0 and default_interest_pct <= 20),
  monthly_quota         numeric(12,2) not null default 0 check (monthly_quota >= 0),
  status                text not null default 'open' check (status in ('open','closed')),
  created_at            timestamptz not null default now(),
  closed_at             timestamptz
);

create table if not exists caixinha_members (
  id            uuid primary key default gen_random_uuid(),
  caixinha_id   uuid not null references caixinhas(id) on delete cascade,
  profile_id    uuid references profiles(id) on delete set null, -- null = sem conta ainda
  name          text not null,
  last_name     text,
  phone         text,
  role          text not null default 'member' check (role in ('owner','treasurer','member','borrower')),
  -- borrowers não têm aceite; entram como 'accepted' direto.
  invite_status text not null default 'pending' check (invite_status in ('pending','accepted','declined')),
  created_at    timestamptz not null default now(),
  unique (caixinha_id, profile_id)
);

create table if not exists caixinha_contributions (
  id           uuid primary key default gen_random_uuid(),
  caixinha_id  uuid not null references caixinhas(id) on delete cascade,
  member_id    uuid not null references caixinha_members(id) on delete cascade,
  amount       numeric(12,2) not null check (amount > 0),
  date         timestamptz not null default now()
);

create table if not exists caixinha_loans (
  id                 uuid primary key default gen_random_uuid(),
  caixinha_id        uuid not null references caixinhas(id) on delete cascade,
  borrower_member_id uuid not null references caixinha_members(id) on delete cascade,
  borrower_name      text not null,
  principal          numeric(12,2) not null check (principal > 0),
  interest_pct       numeric(5,2) not null default 0 check (interest_pct >= 0 and interest_pct <= 20),
  date               timestamptz not null default now(),
  due_date           timestamptz
);

create table if not exists caixinha_earnings (
  id           uuid primary key default gen_random_uuid(),
  caixinha_id  uuid not null references caixinhas(id) on delete cascade,
  amount       numeric(12,2) not null check (amount > 0),
  source       text not null check (source in ('investment','loanInterest')),
  loan_id      uuid references caixinha_loans(id) on delete cascade,
  note         text,
  date         timestamptz not null default now()
);

create table if not exists caixinha_loan_payments (
  id           uuid primary key default gen_random_uuid(),
  caixinha_id  uuid not null references caixinhas(id) on delete cascade,
  loan_id      uuid not null references caixinha_loans(id) on delete cascade,
  amount       numeric(12,2) not null check (amount > 0),
  note         text,
  date         timestamptz not null default now()
);

-- ---------- Funções auxiliares (SECURITY DEFINER; evitam recursão de RLS) ----------
create or replace function public.is_caixinha_owner(cid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(select 1 from caixinhas c where c.id = cid and c.owner_id = auth.uid());
$$;

-- Qualquer vínculo (inclui borrower) — usado só para ler a caixinha em si.
create or replace function public.is_caixinha_member(cid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select public.is_caixinha_owner(cid) or exists(
    select 1 from caixinha_members m where m.caixinha_id = cid and m.profile_id = auth.uid()
  );
$$;

-- Quem pode LANÇAR (dono + tesoureiros).
create or replace function public.is_caixinha_treasurer(cid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select public.is_caixinha_owner(cid) or exists(
    select 1 from caixinha_members m
    where m.caixinha_id = cid and m.profile_id = auth.uid() and m.role in ('owner','treasurer')
  );
$$;

-- Quem participa da POUPANÇA (vê aportes/rendimentos/todos os membros).
-- Exclui borrower de propósito.
create or replace function public.caixinha_can_see_all(cid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select public.is_caixinha_owner(cid) or exists(
    select 1 from caixinha_members m
    where m.caixinha_id = cid and m.profile_id = auth.uid() and m.role in ('owner','treasurer','member')
  );
$$;

-- Anti-escalada: numa auto-atualização (o próprio membro), só invite_status
-- pode mudar — ninguém se promove a tesoureiro. Tesoureiro/dono passam livres.
create or replace function public.enforce_caixinha_self_accept()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_caixinha_treasurer(NEW.caixinha_id) then
    return NEW;
  end if;
  if OLD.profile_id is distinct from auth.uid() then
    raise exception 'Sem permissão para alterar este membro.';
  end if;
  if NEW.role is distinct from OLD.role then
    raise exception 'Não é possível alterar o próprio papel.';
  end if;
  return NEW;
end;
$$;

drop trigger if exists caixinha_self_accept on caixinha_members;
create trigger caixinha_self_accept
  before update on caixinha_members
  for each row execute function public.enforce_caixinha_self_accept();

-- Garante que o papel autenticado pode executar os helpers usados nas policies
-- (alguns projetos revogam o EXECUTE default; sem isso a RLS negaria tudo).
grant execute on function public.is_caixinha_owner(uuid) to authenticated;
grant execute on function public.is_caixinha_member(uuid) to authenticated;
grant execute on function public.is_caixinha_treasurer(uuid) to authenticated;
grant execute on function public.caixinha_can_see_all(uuid) to authenticated;

-- ---------- RLS ----------
alter table caixinhas              enable row level security;
alter table caixinha_members       enable row level security;
alter table caixinha_contributions enable row level security;
alter table caixinha_loans         enable row level security;
alter table caixinha_earnings      enable row level security;
alter table caixinha_loan_payments enable row level security;

-- caixinhas: qualquer vínculo lê (borrower vê o nome/contexto); dono cria/edita/apaga.
drop policy if exists "cx read" on caixinhas;
create policy "cx read" on caixinhas
  for select using (public.is_caixinha_member(id));
drop policy if exists "cx insert" on caixinhas;
create policy "cx insert" on caixinhas
  for insert with check (owner_id = auth.uid());
drop policy if exists "cx modify" on caixinhas;
create policy "cx modify" on caixinhas
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "cx delete" on caixinhas;
create policy "cx delete" on caixinhas
  for delete using (owner_id = auth.uid());

-- membros: quem participa vê todos; o borrower vê só a própria linha.
drop policy if exists "cxm read" on caixinha_members;
create policy "cxm read" on caixinha_members
  for select using (public.caixinha_can_see_all(caixinha_id) or profile_id = auth.uid());
drop policy if exists "cxm treasurer manage" on caixinha_members;
create policy "cxm treasurer manage" on caixinha_members
  for all using (public.is_caixinha_treasurer(caixinha_id)) with check (public.is_caixinha_treasurer(caixinha_id));
drop policy if exists "cxm accept self" on caixinha_members;
create policy "cxm accept self" on caixinha_members
  for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- contribuições: só quem participa da poupança (borrower não vê).
drop policy if exists "cxc read" on caixinha_contributions;
create policy "cxc read" on caixinha_contributions
  for select using (public.caixinha_can_see_all(caixinha_id));
drop policy if exists "cxc write" on caixinha_contributions;
create policy "cxc write" on caixinha_contributions
  for all using (public.is_caixinha_treasurer(caixinha_id)) with check (public.is_caixinha_treasurer(caixinha_id));

-- rendimentos: idem.
drop policy if exists "cxe read" on caixinha_earnings;
create policy "cxe read" on caixinha_earnings
  for select using (public.caixinha_can_see_all(caixinha_id));
drop policy if exists "cxe write" on caixinha_earnings;
create policy "cxe write" on caixinha_earnings
  for all using (public.is_caixinha_treasurer(caixinha_id)) with check (public.is_caixinha_treasurer(caixinha_id));

-- empréstimos: quem participa vê todos; o tomador vê só o(s) seu(s).
drop policy if exists "cxl read" on caixinha_loans;
create policy "cxl read" on caixinha_loans
  for select using (
    public.caixinha_can_see_all(caixinha_id)
    or exists(select 1 from caixinha_members m where m.id = borrower_member_id and m.profile_id = auth.uid())
  );
drop policy if exists "cxl write" on caixinha_loans;
create policy "cxl write" on caixinha_loans
  for all using (public.is_caixinha_treasurer(caixinha_id)) with check (public.is_caixinha_treasurer(caixinha_id));

-- pagamentos de empréstimo: quem participa vê todos; o tomador vê os seus.
drop policy if exists "cxlp read" on caixinha_loan_payments;
create policy "cxlp read" on caixinha_loan_payments
  for select using (
    public.caixinha_can_see_all(caixinha_id)
    or exists(
      select 1 from caixinha_loans l
      join caixinha_members m on m.id = l.borrower_member_id
      where l.id = loan_id and m.profile_id = auth.uid()
    )
  );
drop policy if exists "cxlp write" on caixinha_loan_payments;
create policy "cxlp write" on caixinha_loan_payments
  for all using (public.is_caixinha_treasurer(caixinha_id)) with check (public.is_caixinha_treasurer(caixinha_id));

-- ---------- Realtime (sinal de invalidação; RLS já filtra por usuário) ----------
do $$
declare
  t text;
  tables text[] := array[
    'caixinhas', 'caixinha_members', 'caixinha_contributions',
    'caixinha_loans', 'caixinha_earnings', 'caixinha_loan_payments'
  ];
begin
  foreach t in array tables loop
    execute format('alter table public.%I replica identity full;', t);
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I;', t);
    end if;
  end loop;
end $$;
