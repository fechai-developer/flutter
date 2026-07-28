-- =====================================================================
-- Fechaí — Remoção de membro com preservação de histórico
-- =====================================================================
-- Regra de produto:
--  - Só remove quem está ZERADO (sem saldo em aberto) — trava no servidor.
--  - Nunca teve movimentação → remove de vez (some para a pessoa).
--  - Já teve movimentação → remoção "leve": a pessoa sai das movimentações
--    ativas, mas mantém acesso SOMENTE-LEITURA ao histórico das despesas em
--    que se envolveu (pagando/cobrando/participando do rateio) + consolidado.
--
-- Implementação: coluna `removed_at`. Linha preservada quando há histórico.
--  - `is_group_member`/`is_sub_member` passam a contar só ATIVOS (removed_at null)
--    → o removido perde leitura ampla e escrita automaticamente.
--  - `was_group_member`/`was_sub_member` (qualquer linha) + `involved_in_expense`
--    devolvem ao removido o acesso pontual ao próprio histórico.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Coluna de remoção (soft delete de vínculo)
-- ---------------------------------------------------------------------
alter table group_members        add column if not exists removed_at timestamptz;
alter table subscription_members add column if not exists removed_at timestamptz;

-- ---------------------------------------------------------------------
-- 2) Helpers: "membro ativo" (só removed_at null) x "já foi membro" (qualquer)
-- ---------------------------------------------------------------------
create or replace function public.is_group_member(gid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(
    select 1 from group_members gm
    where gm.group_id = gid and gm.profile_id = auth.uid() and gm.removed_at is null
  );
$$;

create or replace function public.was_group_member(gid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(
    select 1 from group_members gm
    where gm.group_id = gid and gm.profile_id = auth.uid()
  );
$$;

create or replace function public.is_sub_member(sid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(
    select 1 from subscription_members sm
    where sm.subscription_id = sid and sm.profile_id = auth.uid() and sm.removed_at is null
  );
$$;

create or replace function public.was_sub_member(sid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(
    select 1 from subscription_members sm
    where sm.subscription_id = sid and sm.profile_id = auth.uid()
  );
$$;

-- Compartilho contexto ATIVO com `other` E ele aceitou? (#7)
-- Um membro removido para de vazar/receber nome+PIX via payee_info.
create or replace function public.shares_context_with(other uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(
    select 1
    from group_members me
    join group_members them on them.group_id = me.group_id
    where me.profile_id = auth.uid() and me.removed_at is null
      and them.profile_id = other and them.removed_at is null
      and them.status = 'accepted'
  ) or exists(
    select 1
    from subscription_members me
    join subscription_members them on them.subscription_id = me.subscription_id
    where me.profile_id = auth.uid() and me.removed_at is null
      and them.profile_id = other and them.removed_at is null
      and them.invite_status = 'accepted'
  );
$$;

-- O usuário logado está envolvido nesta despesa? (pagou OU tem cota no rateio)
-- Vale mesmo para linha de membro já removida — é o que dá ao ex-membro acesso
-- somente ao próprio histórico.
create or replace function public.involved_in_expense(eid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(
    select 1
    from expenses e
    join group_members gm on gm.group_id = e.group_id and gm.profile_id = auth.uid()
    where e.id = eid
      and (
        e.paid_by = gm.id
        or exists(select 1 from expense_shares es where es.expense_id = e.id and es.member_id = gm.id)
      )
  );
$$;

-- ---------------------------------------------------------------------
-- 3) RLS — devolve ao removido o acesso pontual ao histórico
-- ---------------------------------------------------------------------
-- groups: dono, membro ativo OU ex-membro (para o cabeçalho do arquivo)
drop policy if exists "groups read" on groups;
create policy "groups read" on groups
  for select using (owner_id = auth.uid() or public.was_group_member(id));

-- group_members: membro/dono OU ex-membro (resolve nomes do histórico)
drop policy if exists "gm read" on group_members;
create policy "gm read" on group_members
  for select using (
    public.is_group_member(group_id)
    or public.is_group_owner(group_id)
    or public.was_group_member(group_id)
  );

-- expenses: leitura ampla p/ ativos + pontual p/ envolvido; escrita só ativos.
drop policy if exists "exp member" on expenses;
drop policy if exists "exp select" on expenses;
drop policy if exists "exp insert" on expenses;
drop policy if exists "exp update" on expenses;
drop policy if exists "exp delete" on expenses;
create policy "exp select" on expenses
  for select using (public.is_group_member(group_id) or public.involved_in_expense(id));
create policy "exp insert" on expenses
  for insert with check (public.is_group_member(group_id));
create policy "exp update" on expenses
  for update using (public.is_group_member(group_id)) with check (public.is_group_member(group_id));
create policy "exp delete" on expenses
  for delete using (public.is_group_member(group_id));

-- expense_shares: acompanha a despesa (leitura pontual p/ envolvido)
drop policy if exists "share member" on expense_shares;
drop policy if exists "share select" on expense_shares;
drop policy if exists "share insert" on expense_shares;
drop policy if exists "share update" on expense_shares;
drop policy if exists "share delete" on expense_shares;
create policy "share select" on expense_shares
  for select using (
    exists(select 1 from expenses e where e.id = expense_id
      and (public.is_group_member(e.group_id) or public.involved_in_expense(e.id)))
  );
create policy "share insert" on expense_shares
  for insert with check (
    exists(select 1 from expenses e where e.id = expense_id and public.is_group_member(e.group_id))
  );
create policy "share update" on expense_shares
  for update using (
    exists(select 1 from expenses e where e.id = expense_id and public.is_group_member(e.group_id))
  ) with check (
    exists(select 1 from expenses e where e.id = expense_id and public.is_group_member(e.group_id))
  );
create policy "share delete" on expense_shares
  for delete using (
    exists(select 1 from expenses e where e.id = expense_id and public.is_group_member(e.group_id))
  );

-- payments: membro ativo lê tudo; ex-membro lê os acertos em que entrou.
drop policy if exists "pay read" on payments;
create policy "pay read" on payments
  for select using (
    public.is_group_member(group_id)
    or exists(
      select 1 from group_members gm
      where gm.id in (from_member, to_member) and gm.profile_id = auth.uid()
    )
  );

-- subscriptions: dono, membro ativo OU ex-membro
drop policy if exists "sub read" on subscriptions;
create policy "sub read" on subscriptions
  for select using (owner_id = auth.uid() or public.was_sub_member(id));

drop policy if exists "sm read" on subscription_members;
create policy "sm read" on subscription_members
  for select using (
    public.is_sub_member(subscription_id)
    or public.is_sub_owner(subscription_id)
    or public.was_sub_member(subscription_id)
  );

-- ---------------------------------------------------------------------
-- 4) RPCs de remoção (autoritativas): dono OU o próprio (auto-saída)
-- ---------------------------------------------------------------------
create or replace function public.remove_group_member(p_member_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  m record;
  net numeric;
  has_history boolean;
begin
  select gm.id, gm.group_id, gm.profile_id, g.owner_id
    into m
    from group_members gm
    join groups g on g.id = gm.group_id
    where gm.id = p_member_id;
  if not found then
    raise exception 'Membro não encontrado';
  end if;

  -- autoriza: dono do grupo ou o próprio membro
  if m.owner_id <> auth.uid() and m.profile_id is distinct from auth.uid() then
    raise exception 'Sem permissão para remover este membro';
  end if;

  -- o dono não sai do próprio grupo por aqui (usar excluir grupo)
  if m.profile_id = m.owner_id then
    raise exception 'O dono não pode sair do próprio grupo; exclua o grupo.';
  end if;

  -- saldo líquido do membro (mesma conta do BalanceCalculator do app)
  select
      coalesce((select sum(amount) from expenses       where paid_by     = p_member_id), 0)
    - coalesce((select sum(share)  from expense_shares  where member_id   = p_member_id), 0)
    + coalesce((select sum(amount) from payments        where from_member = p_member_id), 0)
    - coalesce((select sum(amount) from payments        where to_member   = p_member_id), 0)
    into net;
  if abs(coalesce(net, 0)) > 0.01 then
    raise exception 'Membro com saldo em aberto; acerte antes de remover.';
  end if;

  has_history :=
       exists(select 1 from expenses       where paid_by   = p_member_id)
    or exists(select 1 from expense_shares where member_id = p_member_id)
    or exists(select 1 from payments       where from_member = p_member_id or to_member = p_member_id);

  if has_history then
    update group_members set removed_at = now() where id = p_member_id;
  else
    delete from group_members where id = p_member_id;
  end if;
end;
$$;

create or replace function public.remove_subscription_member(p_member_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  m record;
begin
  select sm.id, sm.profile_id, sm.status, sm.months_late, sm.invite_status, s.owner_id
    into m
    from subscription_members sm
    join subscriptions s on s.id = sm.subscription_id
    where sm.id = p_member_id;
  if not found then
    raise exception 'Participante não encontrado';
  end if;

  if m.owner_id <> auth.uid() and m.profile_id is distinct from auth.uid() then
    raise exception 'Sem permissão para remover este participante';
  end if;

  if m.profile_id = m.owner_id then
    raise exception 'O dono não pode sair da própria assinatura; exclua a assinatura.';
  end if;

  -- cota em aberto = participante que aceitou mas não quitou o ciclo
  if m.invite_status = 'accepted' and (m.status <> 'paid' or coalesce(m.months_late, 0) > 0) then
    raise exception 'Participante com cota em aberto; quite antes de remover.';
  end if;

  if m.invite_status = 'accepted' then
    update subscription_members set removed_at = now() where id = p_member_id;
  else
    delete from subscription_members where id = p_member_id;
  end if;
end;
$$;

-- =====================================================================
-- Auditoria rápida (logado como usuário de teste):
--   -- removido só enxerga as despesas em que entrou:
--   select public.remove_group_member('<gm-de-alguem-zerado>');   -- dono
--   -- com saldo deve FALHAR:
--   select public.remove_group_member('<gm-com-saldo>');          -- erro esperado
--   -- ex-membro NÃO escreve:
--   insert into expenses(...) values (...);                        -- erro (RLS) p/ removido
-- =====================================================================
