-- Categoria (tipo) de gasto para despesas e assinaturas.
-- Texto livre nulável, com teto de caracteres validado no servidor (permite
-- tipos sugeridos pelo app e também um tipo próprio do usuário). Não há tabela
-- de apoio nem enum de propósito: 1 coluna, custo mínimo de leitura/escrita.
alter table expenses
  add column if not exists category text
    check (category is null or char_length(category) <= 24);

alter table subscriptions
  add column if not exists category text
    check (category is null or char_length(category) <= 24);
