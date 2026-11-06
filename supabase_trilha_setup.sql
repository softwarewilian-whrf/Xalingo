-- Execute no SQL Editor do mesmo projeto Supabase usado pelo jogo.
-- A autenticação anônima deve estar habilitada em Authentication > Sign In / Providers.

create table if not exists public.trilha_salas (
  code text primary key check (code ~ '^[A-Z0-9]{6}$'),
  host_id uuid not null references auth.users(id) on delete cascade,
  guest_id uuid references auth.users(id) on delete set null,
  status text not null default 'waiting' check (status in ('waiting','playing','finished')),
  state jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trilha_distinct_players check (guest_id is null or guest_id <> host_id)
);

create index if not exists trilha_salas_status_idx on public.trilha_salas(status);
alter table public.trilha_salas enable row level security;

-- Usuários autenticados (incluindo sessões anônimas) podem consultar salas
-- para localizar um código e verificar se há vaga.
drop policy if exists "trilha_select_authenticated" on public.trilha_salas;
create policy "trilha_select_authenticated"
on public.trilha_salas for select to authenticated
using (true);

-- Somente o próprio usuário pode criar sala como anfitrião.
drop policy if exists "trilha_insert_host" on public.trilha_salas;
create policy "trilha_insert_host"
on public.trilha_salas for insert to authenticated
with check (auth.uid() = host_id and guest_id is null and status = 'waiting');

-- Apenas participantes da sala podem atualizar seu estado ou aceitar o convite.
drop policy if exists "trilha_update_participants" on public.trilha_salas;
create policy "trilha_update_participants"
on public.trilha_salas for update to authenticated
using (auth.uid() = host_id or auth.uid() = guest_id or (guest_id is null and status = 'waiting'))
with check (auth.uid() = host_id or auth.uid() = guest_id);

-- Habilita eventos Postgres Changes para sincronização em tempo real.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'trilha_salas'
  ) then
    alter publication supabase_realtime add table public.trilha_salas;
  end if;
end $$;
