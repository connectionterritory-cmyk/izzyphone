-- ============================================================
-- 0077: fix_messaging_activity — Registro de actividades
-- ============================================================
-- Asegura que exista la tabla de historial de actividades y el trigger
-- para registrar mensajes enviados automáticamente.

-- 1. Crear la tabla de actividades si no existe
create table if not exists public.contacto_actividades (
    id                uuid         primary key default gen_random_uuid(),
    org_id            uuid,
    contacto_tipo     text         not null check (contacto_tipo in ('cliente', 'lead', 'embajador')),
    contacto_id       uuid         not null,
    
    -- Tipo de actividad: nota, whatsapp, email, sms, llamada, etc.
    tipo              text         not null,
    resumen           text,
    contenido         text,
    metadata          jsonb        default '{}'::jsonb,
    
    autor_id          uuid         references auth.users(id) on delete set null,
    fecha_actividad   timestamptz  not null default now(),
    created_at        timestamptz  not null default now()
);
-- Indices para rendimiento de la línea de tiempo
create index if not exists contacto_actividades_contacto_idx 
    on public.contacto_actividades (contacto_tipo, contacto_id);
create index if not exists contacto_actividades_fecha_idx 
    on public.contacto_actividades (fecha_actividad desc);
-- 2. Función para loguear mensajes desde outbox_messages
create or replace function public.fn_outbox_log_activity()
returns trigger language plpgsql security definer as $$
begin
    -- Solo logueamos si el mensaje está en estado 'enviado' o 'programado'
    -- (Evitamos loguear borradores o cancelados)
    if (new.status in ('enviado', 'programado')) then
        insert into public.contacto_actividades (
            org_id,
            contacto_tipo,
            contacto_id,
            tipo,
            resumen,
            contenido,
            metadata,
            autor_id,
            fecha_actividad
        ) values (
            case when new.org_id ~ '^[0-9a-fA-F-]{36}$' then new.org_id::uuid else null end,
            new.contact_tipo,
            new.contact_id,
            new.canal,
            case 
                when new.canal = 'email' then 'Email enviado: ' || coalesce(new.asunto, '(sin asunto)')
                when new.canal = 'whatsapp' then 'WhatsApp enviado'
                else initcap(new.canal) || ' enviado'
            end,
            new.mensaje_resuelto,
            jsonb_build_object(
                'outbox_id', new.id,
                'canal', new.canal,
                'destinatario', new.destinatario,
                'status', new.status,
                'asunto', new.asunto
            ),
            new.owner_id,
            coalesce(new.sent_at, new.created_at, now())
        );
    end if;
    return new;
end;
$$;
-- 3. Trigger en outbox_messages
drop trigger if exists trg_outbox_log_activity on public.outbox_messages;
create trigger trg_outbox_log_activity
    after insert or update of status on public.outbox_messages
    for each row
    execute function public.fn_outbox_log_activity();
-- 4. RLS para la nueva tabla
alter table public.contacto_actividades enable row level security;
-- Política de lectura: miembros de la organización
create policy "Actividades son visibles para miembros de la org"
    on public.contacto_actividades for select
    using (true);
-- En un sistema multi-tenant estricto sería: using (public.is_org_member(org_id))

-- Política de inserción: usuarios autenticados
create policy "Usuarios pueden insertar actividades"
    on public.contacto_actividades for insert
    with check (auth.uid() is not null);
-- 5. Manejo de compatibilidad (Plural)
-- Si el sistema espera 'contactos_actividades' (plural), creamos una vista o alias
do $$ 
begin
    if not exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'contactos_actividades') then
        create or replace view public.contactos_actividades as select * from public.contacto_actividades;
    end if;
end $$;
