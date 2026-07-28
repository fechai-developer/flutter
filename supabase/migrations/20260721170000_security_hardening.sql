-- =====================================================================
-- Fechaí — Etapa S (Segurança) — endurecimento
-- =====================================================================
-- Decisões (ver IMPLEMENTATION_TODO.md → Etapa S):
--  - Não-interferência: só o PRÓPRIO membro promove seu vínculo p/ 'accepted'
--    (o dono gerencia tudo menos isso). Fecha a escalada de privilégio em que
--    o dono forjava um vínculo aceito p/ vazar nome+PIX via payee_info.
--  - Juros: teto rígido de 20%/mês no banco + gating por plano (só premium).
--  - Freemium: 1 plano pago ('premium') libera limites; travas no SERVIDOR.
--  - LGPD: excluir conta = ANONIMIZAR (preserva histórico dos outros);
--          exportar dados do titular; termo versionado que bloqueia até reaceite.
--  - Anti-enumeração / anti-spam: rate limit em find_profile_by_phone e teto
--          mensal de cobranças no plano free.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Juros: teto rígido no banco (Lei de Usura / abusividade). Ilustrativo, ≤ 20%/mês.
-- ---------------------------------------------------------------------
alter table groups        drop constraint if exists groups_interest_cap;
alter table groups        add  constraint groups_interest_cap check (monthly_interest_pct <= 20);
alter table subscriptions drop constraint if exists subs_interest_cap;
alter table subscriptions add  constraint subs_interest_cap  check (monthly_interest_pct <= 20);

-- ---------------------------------------------------------------------
-- 2) Não-interferência: só o próprio membro aceita seu vínculo.
--    A RLS "gm owner manage"/"sm owner manage" deixa o dono editar as linhas
--    (nome/telefone/cota), mas este trigger impede QUALQUER caminho de virar
--    'accepted' que não seja o próprio dono do vínculo (profile_id = auth.uid()).
-- ---------------------------------------------------------------------
create or replace function public.enforce_self_accept()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'group_members' then
    if new.status = 'accepted'
       and (tg_op = 'INSERT' or old.status is distinct from 'accepted')
       and new.profile_id is distinct from auth.uid() then
      raise exception 'Só o próprio membro pode aceitar o vínculo do grupo';
    end if;
  elsif tg_table_name = 'subscription_members' then
    if new.invite_status = 'accepted'
       and (tg_op = 'INSERT' or old.invite_status is distinct from 'accepted')
       and new.profile_id is distinct from auth.uid() then
      raise exception 'Só o próprio participante pode aceitar o convite da assinatura';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists gm_enforce_self_accept on group_members;
create trigger gm_enforce_self_accept
  before insert or update on group_members
  for each row execute function public.enforce_self_accept();

drop trigger if exists sm_enforce_self_accept on subscription_members;
create trigger sm_enforce_self_accept
  before insert or update on subscription_members
  for each row execute function public.enforce_self_accept();

-- ---------------------------------------------------------------------
-- 3) Plano do usuário (fonte da verdade do premium) + limites configuráveis.
--    O status premium NÃO pode ser alterado pelo próprio usuário (só service_role,
--    ex.: Edge Function de pagamento ou edição manual no painel Supabase).
-- ---------------------------------------------------------------------
alter table profiles add column if not exists plan             text        not null default 'free'
  check (plan in ('free','premium'));
alter table profiles add column if not exists plan_valid_until timestamptz;
alter table profiles add column if not exists deleted_at       timestamptz;   -- LGPD (soft delete/anonimização)

-- Tabela de limites por plano (editável no painel — "fácil manutenção").
-- null = ilimitado.
create table if not exists plan_limits (
  plan              text primary key,
  max_groups        int,      -- grupos que o usuário pode ser DONO
  max_subscriptions int,      -- assinaturas que o usuário pode ser DONO
  monthly_charges   int,      -- "Cobra Aí" por mês-calendário
  allow_interest    boolean not null default false,
  allow_auto_charge boolean not null default false
);

insert into plan_limits (plan, max_groups, max_subscriptions, monthly_charges, allow_interest, allow_auto_charge)
values
  ('free',    3,    2,    30,   false, false),   -- base
  ('premium', 6,    4,    null, true,  true)     -- +3 grupos, +2 assinaturas, Cobra Aí sem limite, juros, automação
on conflict (plan) do update set
  max_groups        = excluded.max_groups,
  max_subscriptions = excluded.max_subscriptions,
  monthly_charges   = excluded.monthly_charges,
  allow_interest    = excluded.allow_interest,
  allow_auto_charge = excluded.allow_auto_charge;

alter table plan_limits enable row level security;
drop policy if exists "plan_limits read" on plan_limits;
create policy "plan_limits read" on plan_limits for select using (auth.role() = 'authenticated');
-- escrita: só service_role (que ignora RLS) — nenhuma policy de write.

-- Plano efetivo (considera validade). Usado nas travas e pela UI.
create or replace function public.effective_plan(uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when p.plan = 'premium' and (p.plan_valid_until is null or p.plan_valid_until > now())
      then 'premium' else 'free'
  end
  from profiles p where p.id = uid;
$$;

create or replace function public.is_premium(uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select public.effective_plan(uid) = 'premium';
$$;

-- Impede o usuário de se auto-promover a premium (a policy "profiles self" é FOR ALL).
-- Se a mudança de plano não vier do service_role, reverte para o valor antigo.
create or replace function public.guard_profile_plan()
returns trigger language plpgsql as $$
begin
  if (new.plan is distinct from old.plan
      or new.plan_valid_until is distinct from old.plan_valid_until)
     and current_user not in ('service_role','postgres','supabase_admin') then
    new.plan := old.plan;
    new.plan_valid_until := old.plan_valid_until;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_plan on profiles;
create trigger profiles_guard_plan
  before update on profiles
  for each row execute function public.guard_profile_plan();

-- ---------------------------------------------------------------------
-- 4) Travas de plano no servidor (freemium não burlável pelo cliente).
-- ---------------------------------------------------------------------
-- 4a) Limite de grupos por dono + gating de juros.
create or replace function public.enforce_group_rules()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  lim record;
  cnt int;
begin
  select * into lim from plan_limits where plan = public.effective_plan(new.owner_id);

  if tg_op = 'INSERT' and lim.max_groups is not null then
    select count(*) into cnt from groups where owner_id = new.owner_id;
    if cnt >= lim.max_groups then
      raise exception 'Limite de grupos do plano atingido (assine o premium para criar mais).';
    end if;
  end if;

  if new.monthly_interest_pct > 0 and not lim.allow_interest then
    raise exception 'Juros por atraso é um recurso premium.';
  end if;

  return new;
end;
$$;

drop trigger if exists groups_enforce_rules on groups;
create trigger groups_enforce_rules
  before insert or update on groups
  for each row execute function public.enforce_group_rules();

-- 4b) Limite de assinaturas por dono + gating de juros.
create or replace function public.enforce_subscription_rules()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  lim record;
  cnt int;
begin
  select * into lim from plan_limits where plan = public.effective_plan(new.owner_id);

  if tg_op = 'INSERT' and lim.max_subscriptions is not null then
    select count(*) into cnt from subscriptions where owner_id = new.owner_id;
    if cnt >= lim.max_subscriptions then
      raise exception 'Limite de assinaturas do plano atingido (assine o premium para adicionar mais).';
    end if;
  end if;

  if new.monthly_interest_pct > 0 and not lim.allow_interest then
    raise exception 'Juros por atraso é um recurso premium.';
  end if;

  return new;
end;
$$;

drop trigger if exists subs_enforce_rules on subscriptions;
create trigger subs_enforce_rules
  before insert or update on subscriptions
  for each row execute function public.enforce_subscription_rules();

-- 4c) Teto mensal de "Cobra Aí" (free) + automação só premium.
create or replace function public.enforce_charge_rules()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  lim record;
  cnt int;
begin
  select * into lim from plan_limits where plan = public.effective_plan(new.owner_id);

  if coalesce(new.stage,'manual') <> 'manual' and not lim.allow_auto_charge then
    raise exception 'Cobrança automática é um recurso premium.';
  end if;

  if lim.monthly_charges is not null then
    select count(*) into cnt from charges
      where owner_id = new.owner_id
        and sent_at >= date_trunc('month', now());
    if cnt >= lim.monthly_charges then
      raise exception 'Limite mensal de cobranças do plano atingido.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists charges_enforce_rules on charges;
create trigger charges_enforce_rules
  before insert on charges
  for each row execute function public.enforce_charge_rules();

-- ---------------------------------------------------------------------
-- 5) Rate limit genérico (anti-enumeração de telefone / anti-spam).
-- ---------------------------------------------------------------------
create table if not exists rate_limits (
  user_id      uuid        not null,
  action       text        not null,
  window_start timestamptz not null,
  count        int         not null default 0,
  primary key (user_id, action, window_start)
);
alter table rate_limits enable row level security;
-- sem policy: só o service_definer/serviço escreve; usuário não lê/escreve direto.

create or replace function public.check_rate_limit(p_action text, p_max int, p_window_secs int)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid   uuid := auth.uid();
  wstart timestamptz;
  c int;
begin
  if uid is null then return; end if;  -- fluxos internos/sem sessão não contam
  wstart := to_timestamp(floor(extract(epoch from now()) / p_window_secs) * p_window_secs);
  insert into rate_limits (user_id, action, window_start, count)
  values (uid, p_action, wstart, 1)
  on conflict (user_id, action, window_start)
    do update set count = rate_limits.count + 1
  returning count into c;
  if c > p_max then
    raise exception 'Muitas requisições em pouco tempo. Tente novamente mais tarde.';
  end if;
end;
$$;

-- Reforça find_profile_by_phone (só id, agora também com rate limit).
-- 60 buscas por hora por usuário — folgado p/ uso legítimo, barra varredura.
create or replace function public.find_profile_by_phone(p text)
returns uuid language plpgsql volatile security definer set search_path = public as $$
declare
  r uuid;
begin
  perform public.check_rate_limit('find_phone', 60, 3600);
  select id into r from profiles
    where phone is not null
      and deleted_at is null
      and public.normalize_phone(phone) = public.normalize_phone(p)
    limit 1;
  return r;
end;
$$;

-- ---------------------------------------------------------------------
-- 6) LGPD — excluir conta (anonimiza, preserva histórico dos outros).
-- ---------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Não autenticado';
  end if;

  -- Anonimiza o perfil (mantém a linha p/ não quebrar histórico dos grupos onde sou dono).
  update profiles
    set name = 'Usuário removido', phone = null, pix_key = null, photo_url = null,
        deleted_at = now()
    where id = uid;

  -- Anonimiza minha exibição nas listas de membros.
  update group_members        set name = 'Usuário removido', phone = null where profile_id = uid;
  update subscription_members set name = 'Usuário removido', phone = null where profile_id = uid;

  -- Apaga minhas cobranças (contêm telefone de terceiros).
  delete from charges where owner_id = uid;
end;
$$;

-- ---------------------------------------------------------------------
-- 7) LGPD — exportar dados do titular (só o que é meu; sem PIX/telefone de terceiros).
-- ---------------------------------------------------------------------
create or replace function public.export_my_data()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'profile',                  (select to_jsonb(p) from profiles p where p.id = auth.uid()),
    'terms_accepted',           (select coalesce(jsonb_agg(t), '[]'::jsonb) from user_terms t where t.user_id = auth.uid()),
    'group_memberships',        (select coalesce(jsonb_agg(gm), '[]'::jsonb) from group_members gm where gm.profile_id = auth.uid()),
    'subscription_memberships', (select coalesce(jsonb_agg(sm), '[]'::jsonb) from subscription_members sm where sm.profile_id = auth.uid()),
    'charges_sent',             (select coalesce(jsonb_agg(c), '[]'::jsonb) from charges c where c.owner_id = auth.uid()),
    'settlements',              (select coalesce(jsonb_agg(pay), '[]'::jsonb) from payments pay
                                   where pay.from_member in (select id from group_members where profile_id = auth.uid())
                                      or pay.to_member   in (select id from group_members where profile_id = auth.uid()))
  );
$$;

-- ---------------------------------------------------------------------
-- 8) Termo de uso versionado — bloqueia até reaceitar quando a versão muda.
--    "Fácil manutenção": bump a versão editando app_config no painel.
-- ---------------------------------------------------------------------
create table if not exists app_config (
  key   text primary key,
  value text not null
);
insert into app_config (key, value) values ('terms_version', '2026-07-21')
  on conflict (key) do nothing;

alter table app_config enable row level security;
drop policy if exists "app_config read" on app_config;
create policy "app_config read" on app_config for select using (auth.role() = 'authenticated');

create or replace function public.current_terms_version()
returns text language sql stable security definer set search_path = public as $$
  select value from app_config where key = 'terms_version';
$$;

-- true = o usuário logado ainda precisa aceitar a versão vigente do termo.
create or replace function public.needs_terms_acceptance()
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from user_terms
    where user_id = auth.uid()
      and version = public.current_terms_version()
  );
$$;

-- =====================================================================
-- Auditoria rápida (rodar logado como usuário de teste):
--   -- escalada de privilégio deve FALHAR:
--   insert into group_members(group_id, profile_id, name, status)
--     values ('<grupo-meu>', '<uuid-da-vitima>', 'x', 'accepted');  -- erro esperado
--   -- juros no free deve FALHAR:
--   update groups set monthly_interest_pct = 5 where id = '<grupo-meu>'; -- erro se free
--   -- auto-promoção a premium deve ser IGNORADA:
--   update profiles set plan = 'premium' where id = auth.uid();
--   select plan from profiles where id = auth.uid();  -- continua 'free'
--   select public.needs_terms_acceptance();
--   select public.export_my_data();
-- =====================================================================
