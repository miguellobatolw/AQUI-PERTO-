create table public.fornecedores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome text not null check (char_length(nome) between 2 and 60),
  tipo text not null check (tipo in ('servico','produto')),
  cat text not null check (char_length(cat) <= 40),
  zonas text[] not null check (array_length(zonas,1) between 1 and 20),
  preco text check (char_length(preco) <= 40),
  descr text check (char_length(descr) <= 240),
  tel text not null check (tel ~ '^[0-9]{9}$'),
  created_at timestamptz not null default now()
);
create index on public.fornecedores using gin (zonas);
alter table public.fornecedores enable row level security;

create policy "ler: todos" on public.fornecedores for select to anon, authenticated using (true);
create policy "inserir: so o proprio" on public.fornecedores for insert to authenticated with check (user_id = auth.uid());
create policy "editar: so o proprio" on public.fornecedores for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "apagar: so o proprio" on public.fornecedores for delete to authenticated using (user_id = auth.uid());
