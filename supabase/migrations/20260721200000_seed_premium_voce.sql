-- =====================================================================
-- Fechaí — conta de teste voce@fechai.test como PREMIUM indeterminado
-- =====================================================================
-- plan_valid_until = null => effective_plan() trata como premium sem expiração.
-- Roda em contexto de migração (postgres), então guard_profile_plan permite a
-- alteração de plano. Se o perfil não existir ainda, atualiza 0 linhas (seguro).
-- =====================================================================

update public.profiles p
  set plan = 'premium', plan_valid_until = null
  from auth.users u
  where u.id = p.id
    and u.email = 'voce@fechai.test';
