-- Medidas corporais (cm) — mesma filosofia de avaliacoes_fisicas: foto do
-- momento, trainer registra, aluno só lê, nunca sobrescreve a anterior.
create table medidas_corporais (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id) on delete cascade,
  trainer_id uuid not null references trainers(id) on delete cascade,
  data date not null default current_date,
  braco_direito numeric, braco_esquerdo numeric,
  ombros numeric, peitoral numeric,
  cintura numeric, abdomen numeric, quadril numeric,
  coxa_direita numeric, coxa_esquerda numeric,
  panturrilha_direita numeric, panturrilha_esquerda numeric,
  created_at timestamptz not null default now()
);
alter table medidas_corporais enable row level security;
create policy "trainer gerencia as medidas dos seus alunos" on medidas_corporais for all
  using (trainer_id = auth.uid()) with check (trainer_id = auth.uid());
create policy "aluno vê suas próprias medidas" on medidas_corporais for select
  using (exists (select 1 from clientes where clientes.id = medidas_corporais.cliente_id and clientes.auth_user_id = auth.uid()));

-- Comparações de fotos salvas — guarda só os ids das fotos escolhidas (a
-- data de cada lado vem de fotos_evolucao.created_at, sem duplicar dado).
create table comparacoes_fotos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id) on delete cascade,
  trainer_id uuid not null references trainers(id) on delete cascade,
  titulo text,
  fotos_antes_ids uuid[] not null default '{}',
  fotos_depois_ids uuid[] not null default '{}',
  created_at timestamptz not null default now()
);
alter table comparacoes_fotos enable row level security;
create policy "trainer gerencia as comparações dos seus alunos" on comparacoes_fotos for all
  using (trainer_id = auth.uid()) with check (trainer_id = auth.uid());
create policy "aluno vê suas próprias comparações" on comparacoes_fotos for select
  using (exists (select 1 from clientes where clientes.id = comparacoes_fotos.cliente_id and clientes.auth_user_id = auth.uid()));

-- Marca quem enviou a foto, pra aluno só poder excluir a própria (pedido do
-- histórico de evolução: aluno exclui só o que ele mesmo enviou).
alter table fotos_evolucao add column enviado_por_aluno boolean not null default false;

drop policy "aluno envia e vê suas próprias fotos" on fotos_evolucao;
create policy "aluno vê suas próprias fotos" on fotos_evolucao for select
  using (exists (select 1 from clientes where clientes.id = fotos_evolucao.cliente_id and clientes.auth_user_id = auth.uid()));
create policy "aluno envia suas próprias fotos" on fotos_evolucao for insert
  with check (enviado_por_aluno = true and exists (select 1 from clientes where clientes.id = fotos_evolucao.cliente_id and clientes.auth_user_id = auth.uid()));
create policy "aluno exclui só as fotos que ele mesmo enviou" on fotos_evolucao for delete
  using (enviado_por_aluno = true and exists (select 1 from clientes where clientes.id = fotos_evolucao.cliente_id and clientes.auth_user_id = auth.uid()));

-- Trainer ganha permissão de cadastrar peso também, sem tirar nada do aluno
-- (antes só tinha select).
drop policy "trainer vê registros de peso dos seus alunos" on registros_peso;
create policy "trainer gerencia registros de peso dos seus alunos" on registros_peso for all
  using (trainer_id = auth.uid()) with check (trainer_id = auth.uid());
alter table registros_peso add column origem text; -- 'anamnese' | null (manual)

-- Peso da anamnese vira o primeiro registro de peso — só na primeira vez
-- que o cliente tiver peso_kg e ainda não tiver nenhum registro_peso, pra
-- nunca sobrescrever um registro manual já existente.
create or replace function public.criar_peso_inicial_da_anamnese()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.peso_kg is not null and not exists (select 1 from registros_peso where cliente_id = new.cliente_id) then
    insert into registros_peso (cliente_id, trainer_id, peso, data, origem)
    values (new.cliente_id, new.trainer_id, new.peso_kg, coalesce(new.respondido_em::date, current_date), 'anamnese')
    on conflict (cliente_id, data) do nothing;
  end if;
  return new;
end;
$$;

create trigger on_anamnese_peso_inicial
  after insert or update of peso_kg on anamnese_respostas
  for each row execute function public.criar_peso_inicial_da_anamnese();
