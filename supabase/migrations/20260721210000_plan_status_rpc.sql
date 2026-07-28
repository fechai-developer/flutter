-- =====================================================================
-- Fechaí — RPC de status do plano para a UI (gating comercial)
-- =====================================================================
-- Devolve, para o usuário logado, o plano efetivo + limites + uso atual,
-- para a interface mostrar estados desabilitados e o upsell do premium.
-- =====================================================================

create or replace function public.my_plan_status()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'plan',       public.effective_plan(auth.uid()),
    'is_premium', public.is_premium(auth.uid()),
    'limits',     (select to_jsonb(pl) from plan_limits pl
                     where pl.plan = public.effective_plan(auth.uid())),
    'usage', jsonb_build_object(
      'active_groups',        (select count(*) from groups
                                 where owner_id = auth.uid() and archived_at is null),
      'active_subscriptions', (select count(*) from subscriptions
                                 where owner_id = auth.uid() and archived_at is null),
      'charges_this_month',   (select count(*) from charges
                                 where owner_id = auth.uid() and sent_at >= date_trunc('month', now()))
    )
  );
$$;
