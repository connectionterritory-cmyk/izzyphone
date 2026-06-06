-- ============================================================
-- 0075_personas_autolink_lead_fallback.sql
--
-- Propósito: Ajuste al trigger trg_lead_autolink_persona para
--   tratar al owner como su propio distribuidor raíz cuando
--   usuarios.distribuidor_padre_id IS NULL.
--
-- Contexto: En 0074 el trigger saltaba 161 leads cuyo owner_id
--   apunta a un distribuidor raíz (distribuidor_padre_id = null).
--   El coalesce(u.distribuidor_padre_id, NEW.owner_id) permite
--   usar el owner_id como org en ese caso, manteniendo el mismo
--   scope de tenant.
-- ============================================================

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

  -- Guarda 3: teléfono muy corto → dato inválido
  v_telefono_norm := public.normalizar_telefono(NEW.telefono);
  if length(v_telefono_norm) < 7 then
    return NEW;
  end if;

  -- Resolver org: distribuidor_padre_id cuando existe,
  -- o el owner mismo si es el nodo raíz (distribuidor_padre_id IS NULL)
  select coalesce(u.distribuidor_padre_id, NEW.owner_id)
  into   v_org_id
  from   public.usuarios u
  where  u.id = NEW.owner_id;

  -- Guarda 4: owner no existe en usuarios → skip
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
