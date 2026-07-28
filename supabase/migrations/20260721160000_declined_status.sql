-- =====================================================================
-- Etapa C — Convite/Social: status 'declined'
-- =====================================================================
-- Um convidado pode RECUSAR o convite (não só aceitar). Ao recusar, o vínculo
-- continua existindo com status 'declined' — some da cobrança, aparece
-- esmaecido com a tag "Recusado", e a pessoa pode aceitar depois (item 6).
--
-- Segurança: `shares_context_with()` exige status='accepted' para expor
-- nome+PIX (payee_info), então um 'declined' NÃO vaza dados de terceiros.
-- As policies "gm accept self" / "sm accept self" já permitem o próprio
-- convidado atualizar o seu status (aceitar/recusar) — nada a alterar aqui.
-- =====================================================================

-- group_members.status: pending | accepted | declined
alter table group_members drop constraint if exists group_members_status_check;
alter table group_members
  add constraint group_members_status_check
  check (status in ('pending', 'accepted', 'declined'));

-- subscription_members.invite_status: pending | accepted | declined
alter table subscription_members drop constraint if exists subscription_members_invite_status_check;
alter table subscription_members
  add constraint subscription_members_invite_status_check
  check (invite_status in ('pending', 'accepted', 'declined'));
