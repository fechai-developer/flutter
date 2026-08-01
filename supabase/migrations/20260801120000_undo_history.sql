-- =====================================================================
-- Fechaí — Desfazer lançamentos pelo histórico (dono)
-- =====================================================================
-- Alguns lançamentos não têm tela de edição própria: uma despesa se corrige na
-- aba Despesas, mas um ACERTO ("já paguei" marcado sem querer) só sai do
-- caminho se for apagado. O app agora oferece "Desfazer" no histórico, restrito
-- ao DONO — aqui vai a permissão correspondente no banco.
--
-- Caixinha (aporte, rendimento, ajuste, saída) já estava coberta: as policies
-- `cxc/cxe/cxx write` (tesoureiro) e `cxa write` (dono) são `for all`, então já
-- incluem delete. Faltava só `payments`, que tinha apenas select + insert.
-- =====================================================================

-- Só o dono da conta apaga um acerto. Os dois envolvidos registram (policy
-- "pay insert involved"), mas desfazer mexe no saldo de outra pessoa — fica com
-- quem responde pela conta.
drop policy if exists "pay delete owner" on payments;
create policy "pay delete owner" on payments
  for delete using (public.is_group_owner(group_id));
