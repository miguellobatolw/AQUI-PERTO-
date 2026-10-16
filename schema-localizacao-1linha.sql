alter table public.fornecedores add column if not exists lat double precision check (lat between -90 and 90), add column if not exists lng double precision check (lng between -180 and 180);
