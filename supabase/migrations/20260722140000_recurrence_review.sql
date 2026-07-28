-- =====================================================================
-- Fechaí — Revisão de recorrência ao remover membro
-- =====================================================================
-- Uma despesa recorrente é um "molde" que gera ocorrências mensais (geração
-- automática = Fase E). Se alguém envolvido sai do grupo, a próxima ocorrência
-- não pode simplesmente recriar a dívida de quem saiu. Marcamos a série:
--   - 'participantLeft': participante do rateio saiu → a geração deve
--     REDIVIDIR entre os ativos (aviso; não bloqueia).
--   - 'payerLeft': quem pagava saiu → precisa REATRIBUIR o pagador antes de
--     gerar (bloqueia a geração da Fase E).
-- Editar a despesa (dono revisa) zera o campo de volta para 'none'.
-- =====================================================================

alter table expenses
  add column if not exists recurrence_review text not null default 'none'
    check (recurrence_review in ('none', 'participantLeft', 'payerLeft'));

-- Recria remove_group_member incluindo a marcação das recorrências afetadas.
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

  if m.owner_id <> auth.uid() and m.profile_id is distinct from auth.uid() then
    raise exception 'Sem permissão para remover este membro';
  end if;

  if m.profile_id = m.owner_id then
    raise exception 'O dono não pode sair do próprio grupo; exclua o grupo.';
  end if;

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

  -- Marca recorrências afetadas (só existem quando há histórico → caminho soft).
  -- 1) Quem pagava saiu → bloqueia a geração até reatribuir.
  update expenses e set recurrence_review = 'payerLeft'
    where e.group_id = m.group_id
      and e.recurrence <> 'none'
      and e.paid_by = p_member_id
      and e.recurrence_review <> 'payerLeft';
  -- 2) Participante do rateio saiu → aviso (não sobrescreve o bloqueio acima).
  update expenses e set recurrence_review = 'participantLeft'
    where e.group_id = m.group_id
      and e.recurrence <> 'none'
      and e.recurrence_review = 'none'
      and e.paid_by <> p_member_id
      and exists(select 1 from expense_shares es where es.expense_id = e.id and es.member_id = p_member_id);
end;
$$;
