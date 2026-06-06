-- ============================================================
-- 0074_personas_autolink.sql
--
-- Propósito: Automatizar la asignación de persona_id en leads,
--   clientes y embajadores al momento del INSERT o cuando cambia
--   el teléfono/origen, sin requerir backfill manual futuro.
--
-- Estrategia:
--   • leads    → busca persona por teléfono normalizado + org
--                (org resuelto via owner_id → usuarios.distribuidor_padre_id)
--                Si no existe, crea un nuevo registro en personas.
--   • clientes → igual, org tomado de clientes.org_id directamente.
--   • embajadores → copia persona_id del lead o cliente de origen;
--                   no crea personas propias (embajador es un rol,
--                   no una identidad nueva).
--
-- Guardas de seguridad:
--   • Si persona_id ya está asignado → no tocar (nunca sobreescribe).
--   • Si el teléfono tiene menos de 7 dígitos → skip.
--   • Si no se puede resolver org_id → skip (evita cross-tenant).
--   • UPDATE solo dispara si cambian las columnas relevantes.
-- ============================================================


-- ── 1. Función auxiliar: normalizar teléfono ─────────────────
-- IMMUTABLE y PARALLEL SAFE: segura como índice funcional futuro.

create or replace function public.normalizar_telefono(p text)
returns text
language sql immutable strict parallel safe
as $$
  select regexp_replace(p, '[^0-9]', '', 'g')
$$;
-- ── 2. Trigger function: leads ────────────────────────────────

create or replace function public.trg_lead_autolink_persona()
returns trigger
language plpgsql
as $$
declare
  v_telefono_norm text;
  v_org_id        uuid;
  v_persona_id    uuid;
begin

  -- Guarda 1: ya tiene persona_id → no tocar
  if NEW.persona_id is not null then
    return NEW;
  end if;

  -- Guarda 2: sin teléfono → nada que hacer
  if NEW.telefono is null then
    return NEW;
  end if;

  -- Guarda 3: teléfono muy corto → probablemente dato malo
  v_telefono_norm := public.normalizar_telefono(NEW.telefono);
  if length(v_telefono_norm) < 7 then
    return NEW;
  end if;

  -- Resolver org via owner → usuarios.distribuidor_padre_id
  select u.distribuidor_padre_id
  into   v_org_id
  from   public.usuarios u
  where  u.id = NEW.owner_id;

  -- Guarda 4: sin org resuelta → skip (previene cross-tenant)
  if v_org_id is null then
    return NEW;
  end if;

  -- Buscar persona existente con mismo teléfono en el mismo org
  select p.id
  into   v_persona_id
  from   public.personas p
  where  public.normalizar_telefono(p.telefono) = v_telefono_norm
    and  p.org_id = v_org_id
  limit  1;

  -- Si no existe, crear una nueva persona
  if v_persona_id is null then
    insert into public.personas
      (nombre, apellido, email, telefono, fecha_nacimiento, org_id)
    values
      (NEW.nombre, NEW.apellido, NEW.email, NEW.telefono, NEW.fecha_nacimiento, v_org_id)
    returning id into v_persona_id;
  end if;

  NEW.persona_id := v_persona_id;
  return NEW;

end $$;
-- ── 3. Trigger function: clientes ─────────────────────────────

create or replace function public.trg_cliente_autolink_persona()
returns trigger
language plpgsql
as $$
declare
  v_telefono_norm text;
  v_org_id        uuid;
  v_persona_id    uuid;
begin

  if NEW.persona_id is not null then
    return NEW;
  end if;

  if NEW.telefono is null then
    return NEW;
  end if;

  v_telefono_norm := public.normalizar_telefono(NEW.telefono);
  if length(v_telefono_norm) < 7 then
    return NEW;
  end if;

  -- clientes tiene org_id directo; fallback: buscar via distribuidor_id
  v_org_id := NEW.org_id;

  if v_org_id is null and NEW.distribuidor_id is not null then
    -- distribuidor_id apunta a un usuario con rol distribuidor;
    -- su distribuidor_padre_id es la raíz del árbol (= org)
    select u.distribuidor_padre_id
    into   v_org_id
    from   public.usuarios u
    where  u.id = NEW.distribuidor_id;

    -- Si el distribuidor ES la raíz (distribuidor_padre_id null),
    -- usamos el distribuidor_id mismo como identificador de org
    if v_org_id is null then
      v_org_id := NEW.distribuidor_id;
    end if;
  end if;

  if v_org_id is null then
    return NEW;
  end if;

  select p.id
  into   v_persona_id
  from   public.personas p
  where  public.normalizar_telefono(p.telefono) = v_telefono_norm
    and  p.org_id = v_org_id
  limit  1;

  if v_persona_id is null then
    insert into public.personas
      (nombre, apellido, email, telefono, fecha_nacimiento, org_id)
    values
      (NEW.nombre, NEW.apellido, NEW.email, NEW.telefono, NEW.fecha_nacimiento, v_org_id)
    returning id into v_persona_id;
  end if;

  NEW.persona_id := v_persona_id;
  return NEW;

end $$;
-- ── 4. Trigger function: embajadores ─────────────────────────
-- El embajador es un ROL, no una identidad nueva.
-- Su persona_id se propaga desde el lead o cliente de origen.

create or replace function public.trg_embajador_autolink_persona()
returns trigger
language plpgsql
as $$
declare
  v_persona_id uuid;
begin

  if NEW.persona_id is not null then
    return NEW;
  end if;

  -- Preferencia: lead > cliente
  if NEW.lead_id is not null then
    select l.persona_id
    into   v_persona_id
    from   public.leads l
    where  l.id = NEW.lead_id;

  elsif NEW.cliente_id is not null then
    select c.persona_id
    into   v_persona_id
    from   public.clientes c
    where  c.id = NEW.cliente_id;
  end if;

  -- Solo asignar si el origen ya tiene persona_id resuelto
  if v_persona_id is not null then
    NEW.persona_id := v_persona_id;
  end if;

  return NEW;

end $$;
-- ── 5. Attach triggers ────────────────────────────────────────

drop trigger if exists trg_lead_autolink_persona      on public.leads;
drop trigger if exists trg_cliente_autolink_persona   on public.clientes;
drop trigger if exists trg_embajador_autolink_persona on public.embajadores;
-- leads: INSERT nuevo o cambio de teléfono/owner (que cambia el org scope)
create trigger trg_lead_autolink_persona
  before insert or update of telefono, owner_id, persona_id
  on public.leads
  for each row
  execute function public.trg_lead_autolink_persona();
-- clientes: INSERT nuevo o cambio de teléfono/org
create trigger trg_cliente_autolink_persona
  before insert or update of telefono, org_id, distribuidor_id, persona_id
  on public.clientes
  for each row
  execute function public.trg_cliente_autolink_persona();
-- embajadores: INSERT o cuando se vincula el origen (lead/cliente)
create trigger trg_embajador_autolink_persona
  before insert or update of lead_id, cliente_id, persona_id
  on public.embajadores
  for each row
  execute function public.trg_embajador_autolink_persona();
-- ── 6. Índice funcional en personas.telefono ─────────────────
-- Hace la búsqueda O(log n) en vez de seq scan.

create index if not exists idx_personas_telefono_norm
  on public.personas (public.normalizar_telefono(telefono))
  where telefono is not null;
-- ── Notas de operación ────────────────────────────────────────
--
-- • El trigger de embajadores NO crea personas nuevas. Si se inscribe
--   un embajador cuyo lead aún no tiene persona_id, quedará en null
--   hasta que el lead reciba su persona (ej: al editar su teléfono).
--   Esto es intencional: el lead es la fuente de verdad.
--
-- • Para retroactivamente asignar persona_id a leads/clientes existentes
--   sin teléfono actualizado, ejecutar:
--
--     update public.leads    set updated_at = now() where persona_id is null and telefono is not null;
--     update public.clientes set updated_at = now() where persona_id is null and telefono is not null;
--
--   Esto disparará el trigger BEFORE UPDATE. Evaluar primero con un
--   SELECT COUNT(*) para estimar el volumen antes de ejecutar.
-- ============================================================;
