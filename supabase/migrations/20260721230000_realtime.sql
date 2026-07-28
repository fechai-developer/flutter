-- =====================================================================
-- Fechaí — Realtime (live update)
-- =====================================================================
-- O app usa o Supabase Realtime apenas como SINAL de invalidação: o cliente
-- escuta `postgres_changes` nestas tabelas e recarrega o provider afetado
-- (ver lib/data/realtime/realtime_sync.dart). A RLS já habilitada (init.sql)
-- é respeitada pelo Realtime, então cada usuário só recebe eventos das linhas
-- que ele pode ler — nenhuma policy nova é necessária.
--
-- Duas coisas precisam existir no banco:
--   1) as tabelas colaborativas dentro da publicação `supabase_realtime`;
--   2) REPLICA IDENTITY FULL nelas, para que eventos UPDATE/DELETE tragam os
--      dados da linha (a RLS precisa avaliar a linha antiga; sem isso, DELETEs
--      chegam só com a PK e podem ser filtrados de forma incorreta).
-- =====================================================================

do $$
declare
  t text;
  tables text[] := array[
    'group_members', 'expenses', 'expense_shares', 'payments',
    'groups', 'subscriptions', 'subscription_members'
  ];
begin
  foreach t in array tables loop
    -- REPLICA IDENTITY FULL (idempotente)
    execute format('alter table public.%I replica identity full;', t);

    -- Adiciona à publicação só se ainda não estiver (evita erro em re-run)
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I;', t);
    end if;
  end loop;
end $$;
