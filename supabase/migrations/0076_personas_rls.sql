-- ============================================================
-- 0076_personas_rls.sql
--
-- Propósito: Endurecer RLS de public.personas.
--
--   Hoy solo existe personas_admin_all (is_admin()).
--   Problema: los triggers trg_*_autolink_persona ejecutan
--   INSERT en personas con los permisos del caller; si el
--   caller es un vendedor, el INSERT falla porque no tiene
--   acceso a personas.
--
-- Cambios:
--   1. personas_distribuidor_all  — distribuidor tiene el
--      mismo acceso que admin (SELECT/INSERT/UPDATE/DELETE).
--   2. personas_vendedor_select   — vendedor solo puede SELECT
--      personas vinculadas a sus leads (owner_id o vendedor_id)
--      o a sus clientes (vendedor_id). Sin INSERT/UPDATE/DELETE.
--   3. Trigger functions re-creadas con SECURITY DEFINER para
--      que el INSERT/UPDATE de personas funcione independiente
--      del rol del caller (vendedor, etc.).
--      SET search_path = public previene search_path injection.
-- ============================================================

-- ── 1. Policy: distribuidor — full access ────────────────────

drop policy if exists personas_distribuidor_all on public.personas;
create policy personas_distribuidor_all on public.personas
  for all
  to authenticated
  using  (public.is_distribuidor())
  with check (public.is_distribuidor());
-- ── 2. Policy: vendedor — SELECT de personas propias ─────────
-- Un vendedor puede ver una persona si tiene al menos un lead
-- o cliente vinculado donde él es owner o vendedor asignado.
-- Esto refleja el mismo scope que leads_select.

drop policy if exists personas_vendedor_select on public.personas;
create policy personas_vendedor_select on public.personas
  for select
  to authenticated
  using (
    public.is_vendedor()
    and (
      -- Persona vinculada a un lead suyo (owner o asignado)
      exists (
        select 1
        from   public.leads l
        where  l.persona_id = personas.id
          and  l.deleted_at is null
          and  (l.owner_id = auth.uid() or l.vendedor_id = auth.uid())
      )
      or
      -- Persona vinculada a un cliente suyo
      exists (
        select 1
        from   public.clientes c
        where  c.persona_id = personas.id
          and  c.vendedor_id = auth.uid()
      )
    )
  );
-- ── 3. Trigger functions con SECURITY DEFINER ────────────────
-- Re-crear con el mismo cuerpo pero añadiendo SECURITY DEFINER
-- y SET search_path para que el INSERT en personas no falle
-- cuando el caller es un vendedor (que solo tiene SELECT).

create or replace function public.trg_lead_autolink_persona()
returns trigger
language plpgsql
security definer
set search_path = public
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

  -- Resolver org: distribuidor_padre_id, o el owner mismo si es raíz
  select coalesce(u.distribuidor_padre_id, NEW.owner_id)
  into   v_org_id
  from   public.usuarios u
  where  u.id = NEW.owner_id;

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
create or replace function public.trg_cliente_autolink_persona()
returns trigger
language plpgsql
security definer
set search_path = public
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

  v_org_id := NEW.org_id;

  if v_org_id is null and NEW.distribuidor_id is not null then
    select u.distribuidor_padre_id
    into   v_org_id
    from   public.usuarios u
    where  u.id = NEW.distribuidor_id;

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
create or replace function public.trg_embajador_autolink_persona()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_persona_id uuid;
begin

  if NEW.persona_id is not null then
    return NEW;
  end if;

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

  if v_persona_id is not null then
    NEW.persona_id := v_persona_id;
  end if;

  return NEW;

end $$;
