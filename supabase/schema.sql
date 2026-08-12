-- Esquema do banco em nuvem do ranking.
--
-- Como aplicar:
--   1. Criar um projeto em https://supabase.com (plano gratuito basta).
--   2. Painel do projeto -> SQL Editor -> New query -> colar este arquivo -> Run.
--   3. Painel -> Project Settings -> API -> copiar "Project URL" e a chave pública.
--   4. Copiar `supabase.cfg.exemplo` para `supabase.cfg`, na raiz do projeto Godot
--      (o .gitignore já cobre esse arquivo), e preencher os dois campos.
--
-- Autenticação é nickname sem senha: não há auth.users nem sessão, e qualquer pessoa
-- pode gravar com qualquer nome. As políticas abaixo permitem INSERT e SELECT ao papel
-- anônimo, e mais nada — ninguém altera nem apaga o placar de ninguém.
--
-- A tabela guarda as contagens POR QUADRANTE, e não só a pontuação final: é o desempenho
-- por categoria que o jogo se propõe a medir.

-- Tabela: uma linha por expediente jogado

create table if not exists public.partidas (
    id              bigint generated always as identity primary key,
    criado_em       timestamptz not null default now(),

    -- Quem e qual dia
    nickname        text    not null check (char_length(nickname) between 2 and 16),
    dia             int     not null check (dia between 1 and 3),
    vitoria         boolean not null default false,

    -- Placar e cronômetro (Etapas 2 e 5)
    pontuacao       int     not null,
    tempo_gasto     real    not null default 0,
    tempo_restante  real    not null default 0,

    -- Nota por categoria da Matriz de Eisenhower (Quadro 1 da Metodologia)
    q1_tarefas      int not null default 0,  -- urgente e importante
    q2_tarefas      int not null default 0,  -- importante, não urgente
    q3_tarefas      int not null default 0,  -- urgente, não importante
    q4_tarefas      int not null default 0,  -- nem urgente nem importante
    q1_pontos       int not null default 0,
    q2_pontos       int not null default 0,
    q3_pontos       int not null default 0,
    q4_pontos       int not null default 0,

    -- Nota por AÇÃO: responde "delegou ou resolveu sozinho?", que a contagem por
    -- categoria sozinha não responde.
    delegou         int not null default 0,
    resolveu        int not null default 0,
    evitou          int not null default 0,
    colidiu         int not null default 0,
    ignorou         int not null default 0,

    interrupcoes    int not null default 0
);

-- O ranking é lido por dia e ordenado por pontuação: é exatamente este índice.
create index if not exists partidas_ranking_idx
    on public.partidas (dia, pontuacao desc, tempo_gasto asc);


-- View: a melhor partida de cada jogador em cada dia
--
-- Sem isso, um jogador insistente ocuparia as dez posições do ranking sozinho.
-- distinct on é do PostgreSQL e resolve isso numa varredura só.

create or replace view public.ranking as
select distinct on (dia, nickname)
    nickname, dia, pontuacao, tempo_gasto, tempo_restante, vitoria,
    q1_tarefas, q2_tarefas, q3_tarefas, q4_tarefas,
    delegou, resolveu, evitou, colidiu, ignorou,
    interrupcoes, criado_em
from public.partidas
order by dia, nickname, pontuacao desc, tempo_gasto asc;


-- Segurança em nível de linha
alter table public.partidas enable row level security;

-- Qualquer um grava a própria partida...
drop policy if exists "anon insere partida" on public.partidas;
create policy "anon insere partida"
    on public.partidas for insert
    to anon, authenticated
    with check (true);

-- ...e qualquer um lê o ranking, de qualquer máquina.
drop policy if exists "anon le partidas" on public.partidas;
create policy "anon le partidas"
    on public.partidas for select
    to anon, authenticated
    using (true);

-- Não existe política de update nem de delete. Com RLS ligada, a ausência de política é
-- negação: o placar é imutável depois de gravado.

-- A view herda a RLS da tabela por baixo quando criada com security_invoker.
alter view public.ranking set (security_invoker = on);
grant select on public.ranking to anon, authenticated;


-- Conferência rápida depois de aplicar
-- insert into public.partidas (nickname, dia, vitoria, pontuacao, tempo_gasto)
--   values ('teste', 1, true, 1200, 61.5);
-- select * from public.ranking where dia = 1;
