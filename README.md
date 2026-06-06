# Izzy Internet — Cotizador de Leads

App web para capturar y enviar leads al equipo de ventas de Izzy Internet. El formulario recopila información del cliente, genera mensajes para WhatsApp y ahora usa Supabase Edge Functions para login, creación y administración de leads sin exponer la tabla `public.izzy_leads` al frontend.

## Supabase

- Proyecto enlazado: `rxiarmbosgivaplygqug` (`FlowSuiteCRM`)
- Funciones:
  - `izzy-admin-leads`: login por PIN, listado y edición de leads
  - `izzy-create-lead`: inserción segura de leads
- Migración incluida:
  - `supabase/migrations/20260606061000_secure_izzy_leads.sql`

## Secrets requeridos

Configura estos secrets antes de desplegar las funciones:

- `SUPABASE_SERVICE_ROLE_KEY`
- `IZZY_SESSION_SECRET`
- `IZZY_USERS_JSON`
- `IZZY_QUOTERS_JSON`

Ejemplo para `IZZY_USERS_JSON`:

```json
[
  { "pin": "XXXX0000", "nombre": "Moises Caicedo", "rol": "admin" },
  { "pin": "YYYY1111", "nombre": "Patricia Caicedo", "rol": "agente" }
]
```

Ejemplo para `IZZY_QUOTERS_JSON`:

```json
[
  { "code": "PCAI", "nombre": "PATRICIA CAICEDO", "telefono": "7862913042" }
]
```
