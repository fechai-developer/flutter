-- =====================================================================
-- Fechaí — Caixinha: sincronização de nome real + autoria no histórico
-- =====================================================================
-- Dois ajustes que faltavam na caixinha e que grupos/assinaturas já têm:
--
-- 1) Nome real ("se conhecem"): os gatilhos de sincronização de nome
--    (stamp_real_name / propagate_profile_name) e o vínculo por telefone
--    (link_memberships) cobriam só group_members e subscription_members.
--    Aqui estendemos para caixinha_members — ao aceitar o convite (ou ao a
--    pessoa se cadastrar depois com o mesmo telefone), o nome sugerido por quem
--    convidou passa a mostrar o nome+sobrenome REAIS do perfil.
--
-- 2) Quem lançou: cada movimentação passa a guardar o autor (recorded_by),
--    preenchido automaticamente com auth.uid() no insert. Numa caixinha o
--    tesoureiro costuma lançar pelos outros, então o histórico mostra tanto a
--    pessoa a que se refere quanto quem registrou.
-- =====================================================================

-- ---------- 1) Sincronização de nome real ----------
-- stamp_real_name() já trata tg_table_name; o ramo padrão usa invite_status,
-- que serve para caixinha_members. Só falta o gatilho.
drop trigger if exists cxm_stamp_real_name on caixinha_members;
create trigger cxm_stamp_real_name
  before insert or update on caixinha_members
  for each row execute function public.stamp_real_name();

-- propagate_profile_name(): ao mudar o próprio nome no perfil, propaga para os
-- vínculos já aceitos — inclui agora as caixinhas.
create or replace function public.propagate_profile_name()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update group_members
    set name = new.name, last_name = new.last_name
    where profile_id = new.id and status = 'accepted';
  update subscription_members
    set name = new.name, last_name = new.last_name
    where profile_id = new.id and invite_status = 'accepted';
  update caixinha_members
    set name = new.name, last_name = new.last_name
    where profile_id = new.id and invite_status = 'accepted';
  return new;
end;
$$;

-- link_memberships(): ao cadastrar/atualizar telefone, liga vínculos pendentes
-- (sem profile_id) — inclui agora as caixinhas.
create or replace function public.link_memberships(p_uid uuid, p_phone text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_phone is null then return; end if;
  update group_members set profile_id = p_uid
    where profile_id is null
      and public.normalize_phone(phone) = public.normalize_phone(p_phone);
  update subscription_members set profile_id = p_uid
    where profile_id is null
      and public.normalize_phone(phone) = public.normalize_phone(p_phone);
  update caixinha_members set profile_id = p_uid
    where profile_id is null
      and public.normalize_phone(phone) = public.normalize_phone(p_phone);
end;
$$;

-- LGPD: anonimização também limpa as linhas de caixinha.
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Não autenticado';
  end if;

  update profiles
    set name = 'Usuário removido', last_name = null, phone = null, pix_key = null,
        photo_url = null, deleted_at = now()
    where id = uid;

  update group_members        set name = 'Usuário removido', last_name = null, phone = null where profile_id = uid;
  update subscription_members set name = 'Usuário removido', last_name = null, phone = null where profile_id = uid;
  update caixinha_members     set name = 'Usuário removido', last_name = null, phone = null where profile_id = uid;

  delete from charges where owner_id = uid;
end;
$$;

-- A trava de auto-aceite (enforce_caixinha_self_accept) deve valer só para
-- chamadas autenticadas via API. Em contexto de servidor/migração (auth.uid()
-- nulo) não há usuário para restringir — libera; senão o backfill abaixo (e
-- qualquer rotina server-side/service-role) esbarra em "Sem permissão".
create or replace function public.enforce_caixinha_self_accept()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return NEW;
  end if;
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

-- Backfill: estampa o nome real nos vínculos de caixinha já aceitos e ligados.
update caixinha_members cm
  set name = p.name, last_name = p.last_name
  from profiles p
  where cm.profile_id = p.id and cm.invite_status = 'accepted'
    and (cm.name is distinct from p.name or cm.last_name is distinct from p.last_name);

-- ---------- 2) Autoria (quem lançou) no histórico ----------
-- default auth.uid() preenche automaticamente no insert sob RLS; linhas antigas
-- ficam null (exibidas sem autor). on delete set null: apagar o perfil não
-- remove a movimentação, só perde a referência de autoria.
alter table caixinha_contributions
  add column if not exists recorded_by uuid references profiles(id) on delete set null default auth.uid();
alter table caixinha_earnings
  add column if not exists recorded_by uuid references profiles(id) on delete set null default auth.uid();
alter table caixinha_adjustments
  add column if not exists recorded_by uuid references profiles(id) on delete set null default auth.uid();
alter table caixinha_exits
  add column if not exists recorded_by uuid references profiles(id) on delete set null default auth.uid();
