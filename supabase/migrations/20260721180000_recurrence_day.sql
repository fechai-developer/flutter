-- Dia do mês em que a despesa recorrente se repete (#2).
-- Antes o dia era implícito (o dia da data do lançamento). Agora o usuário
-- escolhe um dia fixo de 1 a 27 ao ligar a recorrência — igual ao dia de
-- cobrança das assinaturas. Limite 27 para existir em todo mês.
alter table expenses
  add column if not exists recurrence_day int
    check (recurrence_day is null or recurrence_day between 1 and 27);
