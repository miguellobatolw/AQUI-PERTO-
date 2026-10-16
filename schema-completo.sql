-- =====================================================================
-- Aqui Perto — SQL completo das novidades (versão index-216)
--   1) Entrega ao domicílio: raio, taxa, pedido mínimo, entrega grátis
--   2) Programa de moedas (fidelização), opcional por fornecedor
--   3) Total do pedido calculado no servidor (preços, taxa, desconto e total)
-- Correr UMA vez no Supabase (SQL Editor), de uma só vez, ANTES de publicar o index-216.html.
-- É seguro repetir: usa "if not exists" / "or replace" / "drop ... if exists".
-- Pressupõe as tabelas fornecedores e pedidos (com fornecedores.user_id e pedidos.cliente_id)
-- e o schema anterior (incluindo o schema-fotos.sql) já corridos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) ENTREGA AO DOMICÍLIO
-- ---------------------------------------------------------------------
alter table fornecedores
  add column if not exists entrega         boolean       not null default false,
  add column if not exists entrega_raio    numeric,
  add column if not exists entrega_taxa    numeric(8,2),
  add column if not exists entrega_min     numeric(8,2),
  add column if not exists entrega_gratis  numeric(8,2);

alter table pedidos
  add column if not exists entrega boolean       not null default false,
  add column if not exists morada  text,
  add column if not exists taxa    numeric(8,2)  not null default 0;

-- ---------------------------------------------------------------------
-- 2) PROGRAMA DE MOEDAS (FIDELIZAÇÃO)
-- ---------------------------------------------------------------------
alter table fornecedores add column if not exists fidelidade jsonb;

alter table pedidos
  add column if not exists moedas_usadas integer      not null default 0,
  add column if not exists recompensa    text,
  add column if not exists desconto      numeric(8,2) not null default 0;

-- Livro de movimentos (ganho, uso, devolução). Os tipos das colunas de id seguem os das tuas tabelas.
do $$
declare t_f text; t_p text;
begin
  select format_type(atttypid, atttypmod) into t_f from pg_attribute
    where attrelid = 'public.fornecedores'::regclass and attname = 'id';
  select format_type(atttypid, atttypmod) into t_p from pg_attribute
    where attrelid = 'public.pedidos'::regclass and attname = 'id';
  execute format($f$
    create table if not exists public.moedas_mov (
      id            bigint generated always as identity primary key,
      fornecedor_id %s not null,
      cliente_id    uuid not null,
      pedido_id     %s,
      delta         integer not null,
      motivo        text not null check (motivo in ('ganho','uso','devolucao')),
      created_at    timestamptz not null default now()
    )$f$, t_f, t_p);
end $$;

create index if not exists moedas_mov_idx on moedas_mov (fornecedor_id, cliente_id);

alter table moedas_mov enable row level security;
drop policy if exists moedas_ler on moedas_mov;
create policy moedas_ler on moedas_mov for select to authenticated
  using (
    cliente_id = auth.uid()
    or exists (select 1 from fornecedores f where f.id = moedas_mov.fornecedor_id and f.user_id = auth.uid())
  );
-- sem políticas de insert/update/delete: só os triggers abaixo (security definer) escrevem

-- 1) Antes de criar o pedido: valida a recompensa e o saldo
create or replace function pedidos_moedas_antes() returns trigger
language plpgsql security definer set search_path = public as $$
declare f jsonb; v_custo int; v_saldo int; cid uuid := coalesce(new.cliente_id, auth.uid());
begin
  if new.recompensa is null then
    new.moedas_usadas := 0; new.desconto := 0; return new;
  end if;
  select fidelidade into f from fornecedores where id = new.fornecedor_id;
  if f is null or coalesce((f->>'ativo')::boolean, false) = false then
    raise exception 'Fornecedor sem programa de moedas';
  end if;
  if new.recompensa = 'entrega' then v_custo := (f->'ent'->>'custo')::int;
  elsif new.recompensa = 'produto' then v_custo := (f->'prod'->>'custo')::int;
  else raise exception 'Recompensa inválida'; end if;
  if v_custo is null or v_custo <= 0 then raise exception 'Recompensa indisponível'; end if;
  perform pg_advisory_xact_lock(hashtext(new.fornecedor_id::text || cid::text));
  select coalesce(sum(delta), 0) into v_saldo from moedas_mov
    where fornecedor_id = new.fornecedor_id and cliente_id = cid;
  if v_saldo < v_custo then raise exception 'Moedas insuficientes'; end if;
  new.moedas_usadas := v_custo;
  return new;
end $$;

drop trigger if exists trg_pedidos_moedas_antes on pedidos;
create trigger trg_pedidos_moedas_antes before insert on pedidos
  for each row execute function pedidos_moedas_antes();

-- 2) Depois: desconta ao criar; credita ao concluir; devolve ao cancelar
create or replace function pedidos_moedas_depois() returns trigger
language plpgsql security definer set search_path = public as $$
declare f jsonb; cid uuid := coalesce(new.cliente_id, auth.uid()); pts int;
begin
  if tg_op = 'INSERT' then
    if new.moedas_usadas > 0 and cid is not null then
      insert into moedas_mov (fornecedor_id, cliente_id, pedido_id, delta, motivo)
        values (new.fornecedor_id, cid, new.id, -new.moedas_usadas, 'uso');
    end if;
    return new;
  end if;

  if new.estado is distinct from old.estado and cid is not null then
    if new.estado = 'concluido' then
      select fidelidade into f from fornecedores where id = new.fornecedor_id;
      if f is not null and coalesce((f->>'ativo')::boolean, false) then
        pts := floor((new.total - coalesce(new.taxa, 0)) * (f->>'ppe')::numeric);
        if pts > 0 and not exists (select 1 from moedas_mov where pedido_id = new.id and motivo = 'ganho') then
          insert into moedas_mov (fornecedor_id, cliente_id, pedido_id, delta, motivo)
            values (new.fornecedor_id, cid, new.id, pts, 'ganho');
        end if;
      end if;
    elsif new.estado = 'cancelado' and new.moedas_usadas > 0 then
      if not exists (select 1 from moedas_mov where pedido_id = new.id and motivo = 'devolucao') then
        insert into moedas_mov (fornecedor_id, cliente_id, pedido_id, delta, motivo)
          values (new.fornecedor_id, cid, new.id, new.moedas_usadas, 'devolucao');
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_pedidos_moedas_depois on pedidos;
create trigger trg_pedidos_moedas_depois after insert or update of estado on pedidos
  for each row execute function pedidos_moedas_depois();


-- ---------------------------------------------------------------------
-- 3) TOTAL DO PEDIDO CALCULADO NO SERVIDOR
--    A página deixa de ser fonte de verdade: preços, taxa, desconto e total
--    são recalculados aqui a partir dos produtos e da configuração do fornecedor.
--    Corre ANTES do trigger das moedas (o nome começa por "c", o outro por "m").
-- ---------------------------------------------------------------------
create or replace function pedidos_calculo() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  f        record;
  pr       record;
  e        jsonb;
  v_arr    jsonb;
  v_itens  jsonb   := '[]'::jsonb;
  v_seen   text[]  := '{}';
  v_qtd    numeric;
  v_sub    numeric := 0;
  v_taxa   numeric := 0;
  v_desc   numeric := 0;
  v_fid    jsonb;
  v_morada text;
begin
  select * into f from fornecedores where id = new.fornecedor_id;
  if not found then raise exception 'Fornecedor inexistente'; end if;

  -- identidade e estado inicial não vêm da página
  if auth.uid() is not null then new.cliente_id := auth.uid(); end if;
  new.estado := 'novo';

  -- dados do cliente
  new.cliente_nome := btrim(coalesce(new.cliente_nome, ''));
  new.cliente_tel  := regexp_replace(coalesce(new.cliente_tel, ''), '\D', '', 'g');
  if char_length(new.cliente_nome) < 2 or char_length(new.cliente_nome) > 60 then
    raise exception 'Nome inválido';
  end if;
  if new.cliente_tel !~ '^[0-9]{9}$' then raise exception 'Telemóvel inválido'; end if;
  if new.nota is not null then
    new.nota := left(btrim(new.nota), 200);
    if new.nota = '' then new.nota := null; end if;
  end if;

  -- itens: preço, nome, unidade e stock vêm da tabela produtos
  if new.itens is null then raise exception 'Pedido sem itens'; end if;
  v_arr := to_jsonb(new.itens);
  if jsonb_typeof(v_arr) <> 'array' then raise exception 'Pedido sem itens'; end if;
  if jsonb_array_length(v_arr) not between 1 and 50 then raise exception 'Pedido sem itens'; end if;

  for e in select jsonb_array_elements(v_arr) loop
    begin
      v_qtd := (e->>'qtd')::numeric;
    exception when others then
      raise exception 'Quantidade inválida';
    end;
    if v_qtd is null or v_qtd <= 0 or v_qtd > 1000 then raise exception 'Quantidade inválida'; end if;

    select * into pr from produtos
      where id::text = (e->>'pid') and fornecedor_id = new.fornecedor_id and ativo;
    if not found then raise exception 'Produto indisponível'; end if;
    if pr.id::text = any(v_seen) then raise exception 'Produto repetido no pedido'; end if;
    v_seen := v_seen || pr.id::text;
    if pr.stock is not null and v_qtd > pr.stock then
      raise exception 'Stock insuficiente em %', pr.nome;
    end if;

    v_sub   := v_sub + v_qtd * pr.preco;
    v_itens := v_itens || jsonb_build_array(jsonb_build_object(
      'pid', pr.id, 'nome', pr.nome, 'un', pr.un, 'qtd', v_qtd, 'preco', pr.preco));
  end loop;
  v_sub := round(v_sub, 2);

  -- entrega: taxa, mínimo e grátis a partir de
  if new.entrega is true then
    if not coalesce(f.entrega, false) then raise exception 'Este fornecedor não faz entregas'; end if;
    v_morada := btrim(coalesce(new.morada, ''));
    if char_length(v_morada) < 5 then raise exception 'Morada em falta'; end if;
    if coalesce(f.entrega_min, 0) > 0 and v_sub < f.entrega_min then
      raise exception 'Pedido abaixo do mínimo para entrega';
    end if;
    if coalesce(f.entrega_gratis, 0) > 0 and v_sub >= f.entrega_gratis then
      v_taxa := 0;
    else
      v_taxa := coalesce(f.entrega_taxa, 0);
    end if;
    new.morada := left(v_morada, 160);
  else
    new.entrega := false;
    new.morada  := null;
    v_taxa      := 0;
  end if;

  -- recompensa de moedas (o saldo é validado no trigger das moedas)
  if new.recompensa is not null then
    v_fid := f.fidelidade;
    if v_fid is null or not coalesce((v_fid->>'ativo')::boolean, false) then
      raise exception 'Fornecedor sem programa de moedas';
    end if;
    if new.recompensa = 'entrega' then
      if not new.entrega or v_taxa = 0 or coalesce(jsonb_typeof(v_fid->'ent'), 'null') <> 'object' then
        raise exception 'Recompensa indisponível';
      end if;
      v_taxa := 0;
    elsif new.recompensa = 'produto' then
      if coalesce(jsonb_typeof(v_fid->'prod'), 'null') <> 'object' then
        raise exception 'Recompensa indisponível';
      end if;
      v_desc := least((v_fid->'prod'->>'valor')::numeric, v_sub);
    else
      raise exception 'Recompensa inválida';
    end if;
  end if;

  new.itens    := v_itens;
  new.taxa     := round(v_taxa, 2);
  new.desconto := round(v_desc, 2);
  new.total    := round(v_sub - v_desc + v_taxa, 2);
  return new;
end $$;

drop trigger if exists trg_pedidos_calculo on pedidos;
create trigger trg_pedidos_calculo before insert on pedidos
  for each row execute function pedidos_calculo();

-- Depois de criado, os valores do pedido já não podem ser alterados
-- (mudar o estado continua a funcionar). No SQL Editor (sem sessão de utilizador) é permitido.
create or replace function pedidos_proteger() returns trigger
language plpgsql set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if new.fornecedor_id is distinct from old.fornecedor_id
     or new.cliente_id is distinct from old.cliente_id
     or new.itens::text is distinct from old.itens::text
     or new.total is distinct from old.total
     or new.taxa is distinct from old.taxa
     or new.desconto is distinct from old.desconto
     or new.moedas_usadas is distinct from old.moedas_usadas
     or new.recompensa is distinct from old.recompensa
     or new.entrega is distinct from old.entrega then
    raise exception 'Os valores do pedido não podem ser alterados';
  end if;
  return new;
end $$;

drop trigger if exists trg_pedidos_proteger on pedidos;
create trigger trg_pedidos_proteger before update on pedidos
  for each row execute function pedidos_proteger();
