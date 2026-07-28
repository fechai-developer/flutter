-- Vínculo de membros por telefone (#1/#3).
-- Ao adicionar alguém num grupo/assinatura, ligamos ao perfil existente (se já
-- tem conta). Se ainda não tem, fica sem profile_id e é ligado automaticamente
-- quando essa pessoa se cadastrar com o mesmo telefone.

-- Normaliza telefone: só dígitos, tirando DDI 55 quando presente.
create or replace function public.normalize_phone(p text)
returns text language sql immutable as $$
  select case
    when p is null or p = '' then null
    else (
      select case when length(v) in (12, 13) and left(v, 2) = '55' then substr(v, 3) else v end
      from (select regexp_replace(p, '\D', '', 'g') as v) s
    )
  end;
$$;

-- Retorna o id do perfil com aquele telefone (ou null). SECURITY DEFINER para
-- conseguir olhar além da RLS, mas expõe só o id.
create or replace function public.find_profile_by_phone(p text)
returns uuid language sql security definer stable set search_path = public as $$
  select id from profiles
  where phone is not null
    and public.normalize_phone(phone) = public.normalize_phone(p)
  limit 1;
$$;

-- Liga vínculos pendentes (sem profile_id) de um telefone a um usuário.
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
end;
$$;

-- Quando um perfil ganha/atualiza telefone, backfill dos vínculos pendentes.
create or replace function public.on_profile_phone_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.phone is not null then
    perform public.link_memberships(new.id, new.phone);
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_link_memberships on profiles;
create trigger profiles_link_memberships
  after insert or update of phone on profiles
  for each row execute function public.on_profile_phone_change();
