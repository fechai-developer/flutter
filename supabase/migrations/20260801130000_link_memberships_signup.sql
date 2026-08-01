-- =====================================================================
-- Fechaí — Religar vínculos pendentes na criação da conta (robustez)
-- =====================================================================
-- Cenário: alguém cria uma conta/assinatura/caixinha e já cadastra os outros
-- participantes por nome + telefone, antes de eles terem conta. Essas linhas
-- ficam com `profile_id` nulo. Quando a pessoa se cadastra, o vínculo tem que
-- se ligar sozinho ao perfil novo.
--
-- Isso já existia (`link_memberships` + trigger `profiles_link_memberships`),
-- mas dependia de um único caminho dar certo: um UPDATE que listasse a coluna
-- `phone`. Aqui fechamos as brechas que deixavam o vínculo sem ligar:
--
--   1. telefone salvo como string vazia ('' em vez de NULL) nunca casava com
--      nada — e ainda passava pela guarda `if p_phone is null`;
--   2. o gatilho só disparava em `update of phone`; qualquer outro caminho de
--      escrita do perfil não religava;
--   3. o cadastro no Auth podia trazer o telefone (metadata ou `auth.users`)
--      sem que ele chegasse ao perfil;
--   4. quem já tinha se cadastrado antes deste ajuste continuava solto —
--      ninguém reprocessava.
--
-- O que NÃO muda: o vínculo religado continua `pending`. Ligar é reconhecer a
-- pessoa; entrar no grupo continua dependendo do aceite dela.
-- =====================================================================

-- ---------- 1) Telefone vazio vira NULL ----------
-- '' não é telefone: normalize_phone('') devolve NULL e a comparação nunca
-- casa, mas o valor ainda passa por `is not null` e mascara o problema.
create or replace function public.normalize_profile_phone()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.phone is not null and btrim(new.phone) = '' then
    new.phone := null;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_normalize_phone on profiles;
create trigger profiles_normalize_phone
  before insert or update on profiles
  for each row execute function public.normalize_profile_phone();

-- ---------- 2) link_memberships: guarda mais estrita ----------
-- Sai por baixo quando o telefone não normaliza para nada (null, '', só
-- pontuação) — antes de tocar em qualquer tabela.
create or replace function public.link_memberships(p_uid uuid, p_phone text)
returns void language plpgsql security definer set search_path = public as $$
declare
  n text := public.normalize_phone(p_phone);
begin
  if p_uid is null or n is null or n = '' then
    return;
  end if;

  update group_members set profile_id = p_uid
    where profile_id is null and public.normalize_phone(phone) = n;
  update subscription_members set profile_id = p_uid
    where profile_id is null and public.normalize_phone(phone) = n;
  update caixinha_members set profile_id = p_uid
    where profile_id is null and public.normalize_phone(phone) = n;
end;
$$;

-- ---------- 3) Gatilho em qualquer escrita do perfil ----------
-- Antes: `after insert or update of phone`. Um UPDATE que não listasse a
-- coluna `phone` não religava nada. Agora vale para qualquer insert/update com
-- telefone preenchido — a função é idempotente (só mexe em profile_id nulo),
-- então rodar de novo não custa nem estraga.
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
  after insert or update on profiles
  for each row
  when (new.phone is not null)
  execute function public.on_profile_phone_change();

-- ---------- 4) Criação da conta: telefone do Auth vai para o perfil ----------
-- O cadastro é por e-mail + senha, mas o telefone pode chegar por
-- `raw_user_meta_data->>'phone'` (fluxo de convite) ou por `auth.users.phone`
-- (OTP). Levando esse número para o perfil, o gatilho acima religa os vínculos
-- no mesmo instante — sem esperar a tela de completar perfil.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  meta_phone text := nullif(btrim(coalesce(new.raw_user_meta_data->>'phone', new.phone, '')), '');
begin
  insert into public.profiles (id, name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    meta_phone
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ---------- 5) RPC explícita para o app ----------
-- Rede de segurança do lado do cliente: ao salvar o perfil (completar cadastro
-- ou trocar de número), o app chama isto e o vínculo aparece já na primeira
-- carga, sem depender de o gatilho ter rodado. Só religa os vínculos do
-- PRÓPRIO usuário, com o telefone que está no perfil dele.
create or replace function public.link_my_memberships()
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  ph text;
begin
  if uid is null then
    raise exception 'Não autenticado';
  end if;
  select phone into ph from profiles where id = uid;
  perform public.link_memberships(uid, ph);
end;
$$;

revoke all on function public.link_my_memberships() from public;
grant execute on function public.link_my_memberships() to authenticated;

-- ---------- 6) Backfill de quem ficou para trás ----------
-- Reprocessa todo mundo que já tem conta com telefone: quem se cadastrou antes
-- deste ajuste (ou caiu numa das brechas) fica ligado agora.
update profiles set phone = null where phone is not null and btrim(phone) = '';

do $$
declare
  p record;
begin
  for p in select id, phone from profiles where phone is not null loop
    perform public.link_memberships(p.id, p.phone);
  end loop;
end;
$$;

-- Nome real: os vínculos religados que já estavam aceitos passam a mostrar o
-- nome do perfil (e não o que quem convidou digitou). Espelha o backfill de
-- `20260721220000_last_name.sql` / `20260723120000_caixinha_name_sync.sql`.
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

update caixinha_members cm
  set name = p.name, last_name = p.last_name
  from profiles p
  where cm.profile_id = p.id and cm.invite_status = 'accepted'
    and (cm.name is distinct from p.name or cm.last_name is distinct from p.last_name);
