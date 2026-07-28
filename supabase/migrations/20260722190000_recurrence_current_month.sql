-- =====================================================================
-- Fechaí — Recorrência: gerar SÓ o mês corrente (sem catch-up retroativo)
-- =====================================================================
-- Ajuste sobre 20260722180000_recurrence_generation.sql: como o pg_cron roda
-- diariamente, cada mês nasce no dia em que vence — não há necessidade de
-- backfill de meses passados. Gerar retroativo traria cobranças de surpresa
-- (ex.: ligar o cron num app com recorrências antigas). Então a função passa a
-- gerar apenas a ocorrência do MÊS CORRENTE quando vence.
-- Mantém: exclui quem saiu + redivide proporcional mantendo o total; bloqueia
-- se o pagador saiu (payerLeft); idempotente (índice único molde+período).
-- =====================================================================

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
  if p_group_id is null then
    if current_user not in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'Geração global só pelo agendador';
    end if;
  elsif not (public.is_group_member(p_group_id) or public.is_group_owner(p_group_id)) then
    raise exception 'Sem permissão neste grupo';
  end if;

  period := date_trunc('month', p_as_of)::date; -- mês corrente (1º dia)

  for t in
    select e.id, e.group_id, e.description, e.amount, e.paid_by, e.split_type,
           e.date, e.recurrence_day, e.recurrence_until
    from expenses e
    where e.recurrence = 'monthly'
      and e.recurrence_parent_id is null
      and e.recurrence_review <> 'payerLeft'
      and (p_group_id is null or e.group_id = p_group_id)
      and date_trunc('month', e.date) < period            -- o molde já cobre o próprio mês
      and not exists (
        select 1 from group_members gm where gm.id = e.paid_by and gm.removed_at is not null
      )
  loop
    d := least(greatest(coalesce(t.recurrence_day, extract(day from t.date)::int), 1), 28);
    billing := make_date(extract(year from period)::int, extract(month from period)::int, d);

    -- ainda não venceu neste mês, ou passou da data limite → pula
    continue when p_as_of < billing;
    continue when t.recurrence_until is not null and billing > t.recurrence_until;
    -- já existe a ocorrência do mês
    continue when exists (
      select 1 from expenses c where c.recurrence_parent_id = t.id and c.occurrence_period = period
    );

    select coalesce(sum(es.share), 0), count(*)
      into sum_staying, active_count
      from expense_shares es
      join group_members gm on gm.id = es.member_id
      where es.expense_id = t.id and gm.removed_at is null;

    if active_count = 0 then
      continue; -- ninguém ativo no rateio
    end if;

    insert into expenses (group_id, description, amount, paid_by, split_type,
                          date, recurrence, recurrence_parent_id, occurrence_period)
      values (t.group_id, t.description, t.amount, t.paid_by, t.split_type,
              billing, 'none', t.id, period)
      returning id into new_id;

    if sum_staying > 0 then
      insert into expense_shares (expense_id, member_id, share)
        select new_id, es.member_id, round(es.share * t.amount / sum_staying, 2)
        from expense_shares es
        join group_members gm on gm.id = es.member_id
        where es.expense_id = t.id and gm.removed_at is null;
    else
      insert into expense_shares (expense_id, member_id, share)
        select new_id, es.member_id, round(t.amount / active_count, 2)
        from expense_shares es
        join group_members gm on gm.id = es.member_id
        where es.expense_id = t.id and gm.removed_at is null;
    end if;

    select member_id into first_member
      from expense_shares where expense_id = new_id order by member_id limit 1;
    select t.amount - coalesce(sum(share), 0) into diff
      from expense_shares where expense_id = new_id;
    if diff <> 0 and first_member is not null then
      update expense_shares set share = share + diff
        where expense_id = new_id and member_id = first_member;
    end if;

    gen_count := gen_count + 1;
  end loop;

  return gen_count;
end;
$$;
