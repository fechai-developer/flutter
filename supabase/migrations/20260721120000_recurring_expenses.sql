-- Despesa recorrente (#2). A recriação automática das ocorrências mensais é
-- feita por um job agendado (pg_cron + função) na Etapa 3 de automação —
-- aqui ficam apenas as colunas para capturar a intenção.
alter table expenses
  add column if not exists recurrence text not null default 'none'
    check (recurrence in ('none', 'monthly')),
  add column if not exists recurrence_until date;
