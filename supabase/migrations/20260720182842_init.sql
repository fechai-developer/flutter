-- =====================================================================
-- Fechaí — schema Supabase (Postgres) — v2 com RLS completa
-- =====================================================================
-- Rodar no SQL Editor do Supabase (cola tudo e Run).
--
-- IMPORTANTE: o projeto está com "auto-RLS" ligado, então TODA tabela nasce
-- bloqueada até ter política. Este arquivo já traz política pra cada tabela.
--
-- Regras de negócio:
--  - O app NÃO custodia dinheiro (não é PSP). Não há tabela de saldo/carteira.
--  - Privacidade (#7): um usuário só enxerga nome+chave PIX de outro se
--    compartilham um grupo/assinatura E o outro ACEITOU o vínculo. Isso é
--    exposto pela função `payee_info()` (nunca via SELECT direto em profiles).
--  - Convite (#3): membro entra como 'pending'; vira 'accepted' ao confirmar.
--    Só depois de aceitar é que a cobrança/WhatsApp deve ser disparada.
-- =====================================================================

-- ---------- Perfil ----------
create table if not exists profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null default 'Novo usuário',
  phone       text,               -- com DDI, só dígitos
  photo_url   text,
  pix_key     text,               -- chave PIX; nunca dados bancários completos (LGPD)
  created_at  timestamptz not null default now()
);

-- Cria o profile automaticamente quando um usuário se cadastra no Auth.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Termo de uso (#10) ----------
create table if not exists user_terms (
  user_id     uuid not null references profiles(id) on delete cascade,
  version     text not null,
  accepted_at timestamptz not null default now(),
  primary key (user_id, version)
);

-- ---------- Grupos de despesa ----------
create table if not exists groups (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  emoji                 text not null default '💸',
  owner_id              uuid not null references profiles(id) on delete cascade,
  monthly_interest_pct  numeric(5,2) not null default 0 check (monthly_interest_pct >= 0), -- juros em grupo (#8)
  created_at            timestamptz not null default now()
);

create table if not exists group_members (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references groups(id) on delete cascade,
  profile_id  uuid references profiles(id) on delete set null,  -- null = convidado sem conta ainda
  name        text not null,
  phone       text,
  status      text not null default 'pending' check (status in ('pending','accepted')), -- (#3)
  created_at  timestamptz not null default now(),
  unique (group_id, profile_id)
);

create table if not exists expenses (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references groups(id) on delete cascade,
  description   text not null,
  amount        numeric(12,2) not null check (amount > 0),
  paid_by       uuid not null references group_members(id) on delete cascade,
  split_type    text not null check (split_type in ('equal','percentage','weight','exact')),
  date          date not null default current_date,
  created_at    timestamptz not null default now()
);

create table if not exists expense_shares (
  expense_id  uuid not null references expenses(id) on delete cascade,
  member_id   uuid not null references group_members(id) on delete cascade,
  share       numeric(12,2) not null check (share >= 0),
  primary key (expense_id, member_id)
);

-- ---------- Assinaturas compartilhadas ----------
create table if not exists subscriptions (
  id                    uuid primary key default gen_random_uuid(),
  service_name          text not null,
  emoji                 text not null default '📺',
  total_amount          numeric(12,2) not null check (total_amount > 0),
  billing_day           int not null check (billing_day between 1 and 31),
  quota_count           int not null check (quota_count > 0),
  monthly_interest_pct  numeric(5,2) not null default 0 check (monthly_interest_pct >= 0),
  owner_id              uuid not null references profiles(id) on delete cascade,
  created_at            timestamptz not null default now()
);

create table if not exists subscription_members (
  id              uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references subscriptions(id) on delete cascade,
  profile_id      uuid references profiles(id) on delete set null,
  name            text not null,
  phone           text,
  quota           numeric(12,2) not null check (quota >= 0),
  status          text not null default 'pending' check (status in ('pending','paid','overdue')),
  invite_status   text not null default 'pending' check (invite_status in ('pending','accepted')), -- (#3)
  unique (subscription_id, profile_id)
);

-- ---------- Cobranças ("Cobra Aí") ----------
-- Alimenta a North Star (nº de cobranças enviadas/pagas por semana) e o
-- histórico do gráfico (#13). A automação (#9) grava aqui via Edge Function.
create table if not exists charges (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references profiles(id) on delete cascade,
  target_name   text not null,
  target_phone  text,
  amount        numeric(12,2) not null check (amount > 0),
  reason        text not null,
  source_type   text not null check (source_type in ('group','subscription')),
  source_id     uuid,
  pix_payload   text,
  status        text not null default 'sent' check (status in ('sent','paid','canceled')),
  stage         text default 'manual' check (stage in ('manual','d3','d10','d30','recurring')), -- (#9)
  sent_at       timestamptz not null default now(),
  paid_at       timestamptz
);

-- =====================================================================
-- Funções auxiliares (SECURITY DEFINER) — evitam recursão de RLS
-- (uma policy em group_members que consulta group_members entraria em loop;
--  a função roda como owner e ignora RLS internamente).
-- =====================================================================

create or replace function public.is_group_member(gid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(
    select 1 from group_members gm
    where gm.group_id = gid and gm.profile_id = auth.uid()
  );
$$;

create or replace function public.is_group_owner(gid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(select 1 from groups g where g.id = gid and g.owner_id = auth.uid());
$$;

create or replace function public.is_sub_member(sid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(
    select 1 from subscription_members sm
    where sm.subscription_id = sid and sm.profile_id = auth.uid()
  );
$$;

create or replace function public.is_sub_owner(sid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(select 1 from subscriptions s where s.id = sid and s.owner_id = auth.uid());
$$;

-- Compartilho contexto com `other` E ele aceitou o vínculo? (#7)
create or replace function public.shares_context_with(other uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(
    select 1
    from group_members me
    join group_members them on them.group_id = me.group_id
    where me.profile_id = auth.uid()
      and them.profile_id = other
      and them.status = 'accepted'
  ) or exists(
    select 1
    from subscription_members me
    join subscription_members them on them.subscription_id = me.subscription_id
    where me.profile_id = auth.uid()
      and them.profile_id = other
      and them.invite_status = 'accepted'
  );
$$;

-- Único ponto que expõe dados de PAGAMENTO de terceiros: só nome + chave PIX,
-- e só se houver contexto compartilhado aceito. Usar via RPC no app (#7, #C1).
create or replace function public.payee_info(other uuid)
returns table(name text, pix_key text)
language sql security definer stable set search_path = public as $$
  select p.name, p.pix_key
  from profiles p
  where p.id = other and public.shares_context_with(other);
$$;

-- =====================================================================
-- RLS: habilita e cria políticas em TODAS as tabelas
-- =====================================================================
alter table profiles              enable row level security;
alter table user_terms            enable row level security;
alter table groups                enable row level security;
alter table group_members         enable row level security;
alter table expenses              enable row level security;
alter table expense_shares        enable row level security;
alter table subscriptions         enable row level security;
alter table subscription_members  enable row level security;
alter table charges               enable row level security;

-- profiles: cada um lê/edita só o próprio (dados de terceiros só via payee_info)
drop policy if exists "profiles self" on profiles;
create policy "profiles self" on profiles
  for all using (id = auth.uid()) with check (id = auth.uid());

-- user_terms: só o próprio
drop policy if exists "terms self" on user_terms;
create policy "terms self" on user_terms
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- groups: membros leem; dono cria/edita/apaga
drop policy if exists "groups read" on groups;
create policy "groups read" on groups
  for select using (owner_id = auth.uid() or public.is_group_member(id));
drop policy if exists "groups insert" on groups;
create policy "groups insert" on groups
  for insert with check (owner_id = auth.uid());
drop policy if exists "groups modify" on groups;
create policy "groups modify" on groups
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "groups delete" on groups;
create policy "groups delete" on groups
  for delete using (owner_id = auth.uid());

-- group_members: membros do grupo leem a lista; dono gerencia; o convidado
-- pode aceitar o próprio vínculo (update do próprio status).
drop policy if exists "gm read" on group_members;
create policy "gm read" on group_members
  for select using (public.is_group_member(group_id) or public.is_group_owner(group_id));
drop policy if exists "gm owner manage" on group_members;
create policy "gm owner manage" on group_members
  for all using (public.is_group_owner(group_id)) with check (public.is_group_owner(group_id));
drop policy if exists "gm accept self" on group_members;
create policy "gm accept self" on group_members
  for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- expenses: membros do grupo leem e editam
drop policy if exists "exp member" on expenses;
create policy "exp member" on expenses
  for all using (public.is_group_member(group_id)) with check (public.is_group_member(group_id));

-- expense_shares: acompanha a despesa
drop policy if exists "share member" on expense_shares;
create policy "share member" on expense_shares
  for all using (
    exists(select 1 from expenses e where e.id = expense_id and public.is_group_member(e.group_id))
  ) with check (
    exists(select 1 from expenses e where e.id = expense_id and public.is_group_member(e.group_id))
  );

-- subscriptions: membros leem; dono cria/edita/apaga
drop policy if exists "sub read" on subscriptions;
create policy "sub read" on subscriptions
  for select using (owner_id = auth.uid() or public.is_sub_member(id));
drop policy if exists "sub insert" on subscriptions;
create policy "sub insert" on subscriptions
  for insert with check (owner_id = auth.uid());
drop policy if exists "sub modify" on subscriptions;
create policy "sub modify" on subscriptions
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "sub delete" on subscriptions;
create policy "sub delete" on subscriptions
  for delete using (owner_id = auth.uid());

-- subscription_members: membros leem; dono gerencia; participante aceita o próprio
drop policy if exists "sm read" on subscription_members;
create policy "sm read" on subscription_members
  for select using (public.is_sub_member(subscription_id) or public.is_sub_owner(subscription_id));
drop policy if exists "sm owner manage" on subscription_members;
create policy "sm owner manage" on subscription_members
  for all using (public.is_sub_owner(subscription_id)) with check (public.is_sub_owner(subscription_id));
drop policy if exists "sm accept self" on subscription_members;
create policy "sm accept self" on subscription_members
  for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- charges: só o dono da cobrança
drop policy if exists "charges owner" on charges;
create policy "charges owner" on charges
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- =====================================================================
-- Como validar rapidamente (no SQL Editor, logado como um usuário de teste):
--   select * from groups;                 -- deve trazer só os seus
--   select * from public.payee_info('<uuid-de-alguem>');  -- só se compartilham
-- =====================================================================
