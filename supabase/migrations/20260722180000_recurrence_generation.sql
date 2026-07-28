-- =====================================================================
-- Fechaí — Geração das ocorrências de despesas recorrentes (Fase E, item 1)
-- =====================================================================
-- A despesa recorrente é o MOLDE (conta como 1ª ocorrência, no mês do seu date).
-- As ocorrências seguintes são despesas novas ligadas por recurrence_parent_id
-- e marcadas com occurrence_period (1º dia do mês). Um índice único evita
-- duplicar o mesmo mês.
--
-- Regras: exclui quem saiu e redistribui PROPORCIONALMENTE mantendo o total;
-- bloqueia a série se quem pagava saiu (payerLeft / pagador removido).
-- A função é idempotente e faz catch-up de meses vencidos. O agendamento
-- (pg_cron) chama generate_due_recurrences() 1x/dia; um botão "Gerar agora"
-- chama a mesma função escopada a um grupo (por isso o parâmetro p_group_id).
-- =====================================================================

alter table expenses
  add column if not exists recurrence_parent_id uuid references expenses(id) on delete set null,
  add column if not exists occurrence_period date;

-- Não duplica a ocorrência de um mesmo molde+mês.
create unique index if not exists ux_expense_occurrence
  on expenses (recurrence_parent_id, occurrence_period)
  where recurrence_parent_id is not null;

create or replace function public.generate_due_recurrences(
  p_as_of date default current_date,
  p_group_id uuid default null
) returns int language plpgsql security definer set search_path = public as $$
declare
  t             record;
  period        date;
  billing       date;
  d             int;
  gen_count     int := 0;
  new_id        uuid;
  sum_staying   numeric;
  active_count  int;
  first_member  uuid;
  diff          numeric;
begin
  -- Autorização: por grupo exige membro/dono; global (cron) só service_role.
  if p_group_id is null then
    if current_user not in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'Geração global só pelo agendador';
    end if;
  elsif not (public.is_group_member(p_group_id) or public.is_group_owner(p_group_id)) then
    raise exception 'Sem permissão neste grupo';
  end if;

  for t in
    select e.id, e.group_id, e.description, e.amount, e.paid_by, e.split_type,
           e.date, e.recurrence_day, e.recurrence_until
    from expenses e
    where e.recurrence = 'monthly'
      and e.recurrence_parent_id is null
      and e.recurrence_review <> 'payerLeft'
      and (p_group_id is null or e.group_id = p_group_id)
      -- pagador precisa estar ativo (senão é payerLeft e a série fica bloqueada)
      and not exists (
        select 1 from group_members gm where gm.id = e.paid_by and gm.removed_at is not null
      )
  loop
    d := least(greatest(coalesce(t.recurrence_day, extract(day from t.date)::int), 1), 28);
    period := (date_trunc('month', t.date) + interval '1 month')::date;

    while period <= date_trunc('month', p_as_of)::date loop
      billing := make_date(extract(year from period)::int, extract(month from period)::int, d);
      exit when t.recurrence_until is not null and billing > t.recurrence_until;
      exit when p_as_of < billing;

      if not exists (
        select 1 from expenses c
        where c.recurrence_parent_id = t.id and c.occurrence_period = period
      ) then
        -- soma das cotas de quem ficou + quantos ficaram
        select coalesce(sum(es.share), 0), count(*)
          into sum_staying, active_count
          from expense_shares es
          join group_members gm on gm.id = es.member_id
          where es.expense_id = t.id and gm.removed_at is null;

        if active_count > 0 then
          insert into expenses (group_id, description, amount, paid_by, split_type,
                                date, recurrence, recurrence_parent_id, occurrence_period)
            values (t.group_id, t.description, t.amount, t.paid_by, t.split_type,
                    billing, 'none', t.id, period)
            returning id into new_id;

          if sum_staying > 0 then
            -- proporcional, mantendo o total
            insert into expense_shares (expense_id, member_id, share)
              select new_id, es.member_id, round(es.share * t.amount / sum_staying, 2)
              from expense_shares es
              join group_members gm on gm.id = es.member_id
              where es.expense_id = t.id and gm.removed_at is null;
          else
            -- molde com cotas zeradas → divide igual entre os que ficaram
            insert into expense_shares (expense_id, member_id, share)
              select new_id, es.member_id, round(t.amount / active_count, 2)
              from expense_shares es
              join group_members gm on gm.id = es.member_id
              where es.expense_id = t.id and gm.removed_at is null;
          end if;

          -- corrige a sobra de arredondamento na primeira cota (fecha o total)
          select member_id into first_member
            from expense_shares where expense_id = new_id order by member_id limit 1;
          select t.amount - coalesce(sum(share), 0) into diff
            from expense_shares where expense_id = new_id;
          if diff <> 0 and first_member is not null then
            update expense_shares set share = share + diff
              where expense_id = new_id and member_id = first_member;
          end if;

          gen_count := gen_count + 1;
        end if;
      end if;

      period := (period + interval '1 month')::date;
    end loop;
  end loop;

  return gen_count;
end;
$$;

-- Agendamento (rodar no painel, uma vez, com a extensão pg_cron habilitada):
--   select cron.schedule('gerar-recorrencias', '0 6 * * *',
--     $$ select public.generate_due_recurrences(); $$);
