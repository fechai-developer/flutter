-- =====================================================================
-- Fechaí — Nome + Sobrenome
-- =====================================================================
-- Objetivos:
--  - Separar nome e sobrenome (perfil e membros de grupo/assinatura).
--  - Exibir por padrão o PRIMEIRO nome; nome completo só onde faz sentido.
--  - "Se conhecem" (contexto compartilhado + aceite): o nome+sobrenome REAIS
--    do perfil sobrescrevem o que foi "sugerido" por quem convidou. Mesma regra
--    de privacidade já usada para a chave PIX (payee_info / shares_context_with).
-- Regras de exibição:
--  - profiles.name / *_members.name  = PRIMEIRO nome
--  - *.last_name                     = sobrenome (pode ser composto; null = sem)
-- =====================================================================

-- ---------- 1) Colunas ----------
alter table profiles              add column if not exists last_name text;
alter table group_members         add column if not exists last_name text;
alter table subscription_members  add column if not exists last_name text;

-- ---------- 2) Backfill: divide o nome atual no 1º espaço ----------
-- "Ana Prado" -> name='Ana', last_name='Prado'. "Ana" -> name='Ana', last_name=null.
-- Só mexe em quem ainda não tem last_name e cujo name tem espaço.
update profiles set
    last_name = nullif(regexp_replace(name, '^\S+\s+', ''), ''),
    name      = split_part(name, ' ', 1)
  where last_name is null and name like '% %';

update group_members set
    last_name = nullif(regexp_replace(name, '^\S+\s+', ''), ''),
    name      = split_part(name, ' ', 1)
  where last_name is null and name like '% %';

update subscription_members set
    last_name = nullif(regexp_replace(name, '^\S+\s+', ''), ''),
    name      = split_part(name, ' ', 1)
  where last_name is null and name like '% %';

-- ---------- 3) Novo usuário: guarda nome/sobrenome vindos do metadata ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  full_name text := coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1));
begin
  insert into public.profiles (id, name, last_name)
  values (
    new.id,
    split_part(full_name, ' ', 1),
    nullif(regexp_replace(full_name, '^\S+\s+', ''), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ---------- 4) payee_info: agora também expõe o sobrenome ----------
-- Continua sendo o ÚNICO ponto que revela dados de terceiros, e só com contexto
-- compartilhado + aceite (#7).
-- Precisa de DROP: mudar as colunas de retorno não é permitido em CREATE OR REPLACE.
drop function if exists public.payee_info(uuid);
create or replace function public.payee_info(other uuid)
returns table(name text, last_name text, pix_key text)
language sql security definer stable set search_path = public as $$
  select p.name, p.last_name, p.pix_key
  from profiles p
  where p.id = other and public.shares_context_with(other);
$$;

-- ---------- 5) Sincronização do nome real ("se conhecem") ----------
-- Quando um vínculo está LIGADO a um perfil (profile_id) E foi ACEITO, o
-- nome+sobrenome sugeridos por quem convidou são substituídos pelos REAIS do
-- perfil. Assim, o que os outros membros veem passa a ser o nome que a própria
-- pessoa definiu — sem tocar em nenhuma query de leitura.
create or replace function public.stamp_real_name()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  accepted boolean;
  pr record;
begin
  if new.profile_id is null then
    return new;
  end if;

  if tg_table_name = 'group_members' then
    accepted := new.status = 'accepted';
  else
    accepted := new.invite_status = 'accepted';
  end if;

  if not accepted then
    return new;  -- pendente/recusado continua mostrando o nome sugerido (entre aspas)
  end if;

  select name, last_name into pr from profiles where id = new.profile_id;
  if found and pr.name is not null and pr.name <> '' then
    new.name := pr.name;
    new.last_name := pr.last_name;
  end if;
  return new;
end;
$$;

drop trigger if exists gm_stamp_real_name on group_members;
create trigger gm_stamp_real_name
  before insert or update on group_members
  for each row execute function public.stamp_real_name();

drop trigger if exists sm_stamp_real_name on subscription_members;
create trigger sm_stamp_real_name
  before insert or update on subscription_members
  for each row execute function public.stamp_real_name();

-- Quando o perfil muda o próprio nome/sobrenome, propaga para os vínculos já
-- aceitos (os pendentes seguem com o nome sugerido até serem aceitos).
create or replace function public.propagate_profile_name()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update group_members
    set name = new.name, last_name = new.last_name
    where profile_id = new.id and status = 'accepted';
  update subscription_members
    set name = new.name, last_name = new.last_name
    where profile_id = new.id and invite_status = 'accepted';
  return new;
end;
$$;

drop trigger if exists profiles_propagate_name on profiles;
create trigger profiles_propagate_name
  after update of name, last_name on profiles
  for each row
  when (old.name is distinct from new.name or old.last_name is distinct from new.last_name)
  execute function public.propagate_profile_name();

-- Backfill único: estampa o nome real nos vínculos já aceitos e ligados.
update group_members gm
  set name = p.name, last_name = p.last_name
  from profiles p
  where gm.profile_id = p.id and gm.status = 'accepted'
    and (gm.name is distinct from p.name or gm.last_name is distinct from p.last_name);

update subscription_members sm
  set name = p.name, last_name = p.last_name
  from profiles p
  where sm.profile_id = p.id and sm.invite_status = 'accepted'
    and (sm.name is distinct from p.name or sm.last_name is distinct from p.last_name);

-- ---------- 6) LGPD: anonimização também limpa o sobrenome ----------
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

  delete from charges where owner_id = uid;
end;
$$;
