-- =====================================================================
-- Fechaí — Etapa S: limite do plano conta só grupos/assinaturas ATIVOS
-- =====================================================================
-- Correção sobre 20260721170000: as travas de freemium contavam TODOS os
-- grupos/assinaturas que o usuário já criou — então, no free, depois de 3
-- grupos ninguém criava o 4º nunca mais (mesmo com eventos encerrados).
-- Agora o limite conta só os ATIVOS (archived_at is null): arquivar um evento
-- encerrado libera a vaga, e o histórico do arquivado continua acessível.
--
-- Renomeada de 20260721180000 -> 20260721190000 por colisão de versão com
-- 20260721180000_recurrence_day.sql (que ocupou aquele slot).
-- =====================================================================

-- 1) Colunas de arquivamento.
alter table groups        add column if not exists archived_at timestamptz;
alter table subscriptions add column if not exists archived_at timestamptz;

-- 2) Travas recontam só o que está ativo (substituem as versões de 20260721170000).
create or replace function public.enforce_group_rules()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  lim record;
  cnt int;
begin
  select * into lim from plan_limits where plan = public.effective_plan(new.owner_id);

  if tg_op = 'INSERT' and lim.max_groups is not null then
    select count(*) into cnt from groups
      where owner_id = new.owner_id and archived_at is null;
    if cnt >= lim.max_groups then
      raise exception 'Limite de grupos ativos do plano atingido (arquive um grupo encerrado ou assine o premium).';
    end if;
  end if;

  if new.monthly_interest_pct > 0 and not lim.allow_interest then
    raise exception 'Juros por atraso é um recurso premium.';
  end if;

  return new;
end;
$$;

create or replace function public.enforce_subscription_rules()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  lim record;
  cnt int;
begin
  select * into lim from plan_limits where plan = public.effective_plan(new.owner_id);

  if tg_op = 'INSERT' and lim.max_subscriptions is not null then
    select count(*) into cnt from subscriptions
      where owner_id = new.owner_id and archived_at is null;
    if cnt >= lim.max_subscriptions then
      raise exception 'Limite de assinaturas ativas do plano atingido (arquive uma assinatura encerrada ou assine o premium).';
    end if;
  end if;

  if new.monthly_interest_pct > 0 and not lim.allow_interest then
    raise exception 'Juros por atraso é um recurso premium.';
  end if;

  return new;
end;
$$;

-- Os triggers groups_enforce_rules / subs_enforce_rules já existem (20260721170000)
-- e apontam para estas funções — o create or replace acima basta.
