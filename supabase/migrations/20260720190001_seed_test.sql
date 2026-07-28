-- ============================================================
-- SEED de dados de teste (idempotente / guardado).
-- ============================================================
-- PRÉ-REQUISITO: criar 3 usuários no painel (Authentication → Users →
-- Add user, com "Auto Confirm User" ligado), senha igual para facilitar:
--
--   voce@fechai.test   (conta principal de teste)
--   ana@fechai.test
--   bruno@fechai.test
--   senha sugerida:  Fechai123!
--
-- Depois aplique (supabase db push). Se os usuários ainda não existirem,
-- a migração apenas avisa e não insere nada (pode reaplicar depois).
-- Perfil da "voce" fica sem chave PIX de propósito, para você testar a tela
-- de completar perfil no primeiro login.
-- ============================================================

do $$
declare
  v_voce  uuid := (select id from auth.users where email = 'voce@fechai.test');
  v_ana   uuid := (select id from auth.users where email = 'ana@fechai.test');
  v_bruno uuid := (select id from auth.users where email = 'bruno@fechai.test');
  g_id    uuid;
  s_id    uuid;
  gm_voce  uuid;
  gm_ana   uuid;
  gm_bruno uuid;
  e_id    uuid;
begin
  if v_voce is null or v_ana is null or v_bruno is null then
    raise notice 'Seed pulado: crie voce@/ana@/bruno@fechai.test no painel e reaplique.';
    return;
  end if;

  -- Evita duplicar se já rodou
  if exists (select 1 from groups where owner_id = v_voce and name = 'Praia de Maresias') then
    raise notice 'Seed já aplicado, nada a fazer.';
    return;
  end if;

  -- Perfis (o trigger já criou as linhas; aqui ajustamos nome + PIX)
  update profiles set name = 'Ana Prado',  pix_key = 'ana@email.com'   where id = v_ana;
  update profiles set name = 'Bruno Lima', pix_key = '11933334444'     where id = v_bruno;
  update profiles set name = 'Você'                                    where id = v_voce; -- sem PIX de propósito

  -- ---------- Grupo de despesas ----------
  insert into groups (name, emoji, owner_id, monthly_interest_pct)
    values ('Praia de Maresias', '🏖️', v_voce, 1.0) returning id into g_id;

  insert into group_members (group_id, profile_id, name, status)
    values (g_id, v_voce, 'Você', 'accepted') returning id into gm_voce;
  insert into group_members (group_id, profile_id, name, status)
    values (g_id, v_ana, 'Ana Prado', 'accepted') returning id into gm_ana;
  -- Bruno entra como PENDENTE de confirmação (para testar o banner de convite, #1)
  insert into group_members (group_id, profile_id, name, status)
    values (g_id, v_bruno, 'Bruno Lima', 'pending') returning id into gm_bruno;

  -- Despesa 1: Você pagou o aluguel, dividido igual entre os 3
  insert into expenses (group_id, description, amount, paid_by, split_type, date)
    values (g_id, 'Aluguel da casa', 1200.00, gm_voce, 'equal', current_date) returning id into e_id;
  insert into expense_shares (expense_id, member_id, share) values
    (e_id, gm_voce, 400.00), (e_id, gm_ana, 400.00), (e_id, gm_bruno, 400.00);

  -- Despesa 2: Ana pagou o mercado, dividido igual
  insert into expenses (group_id, description, amount, paid_by, split_type, date)
    values (g_id, 'Mercado', 300.00, gm_ana, 'equal', current_date) returning id into e_id;
  insert into expense_shares (expense_id, member_id, share) values
    (e_id, gm_voce, 100.00), (e_id, gm_ana, 100.00), (e_id, gm_bruno, 100.00);

  -- ---------- Assinatura compartilhada ----------
  insert into subscriptions (service_name, emoji, total_amount, billing_day, quota_count, monthly_interest_pct, owner_id)
    values ('Netflix', '🎬', 55.90, 15, 4, 1.0, v_voce) returning id into s_id;

  insert into subscription_members (subscription_id, profile_id, name, quota, status, months_late, invite_status) values
    (s_id, v_voce,  'Você',       13.98, 'paid',    0, 'accepted'),
    (s_id, v_ana,   'Ana Prado',  13.98, 'paid',    0, 'accepted'),
    (s_id, v_bruno, 'Bruno Lima', 13.98, 'overdue', 1, 'accepted');

  raise notice 'Seed aplicado com sucesso.';
end $$;
