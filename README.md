# Izzy Internet — Cotizador de Leads

App web para capturar y enviar leads al equipo de ventas de Izzy Internet. El formulario recopila información del cliente, genera mensajes para WhatsApp y ahora usa Supabase Edge Functions para login, creación y administración de leads sin exponer la tabla `public.izzy_leads` al frontend.

Los accesos del portal ahora pueden tener password persistido en `public.izzy_portal_users`. Los usuarios viejos sin password siguen entrando temporalmente solo con PIN hasta que un admin les asigne password desde `Leads > Administracion`.

El flujo de recuperacion por correo usa `public.izzy_password_reset_requests` para trazabilidad y `public.izzy_password_reset_tokens` para enlaces temporales de un solo uso.

El portal incluye un módulo de `Call Center` en `call-center.html` para operar leads desde un workspace único: registrar llamadas manuales, notas, seguimientos y timeline por lead sin salir del portal.

## Supabase

- Proyecto enlazado: `rxiarmbosgivaplygqug` (`FlowSuiteCRM`)
- Funciones:
  - `izzy-admin-leads`: login por PIN, listado y edición de leads
  - `izzy-create-lead`: inserción segura de leads
  - `izzy-call-center`: workspace operativo para llamadas, actividades y follow-ups
- Migración incluida:
  - `supabase/migrations/20260606061000_secure_izzy_leads.sql`
  - `supabase/migrations/20260615110000_add_izzy_leads_callcenter_fields.sql`
  - `supabase/migrations/20260615111000_create_izzy_lead_activities.sql`
  - `supabase/migrations/20260615112000_create_izzy_lead_calls.sql`
  - `supabase/migrations/20260615113000_create_izzy_followups.sql`

## Call Center

- UI: `call-center.html`
- Edge function: `supabase/functions/izzy-call-center/index.ts`
- Tablas:
  - `public.izzy_lead_calls`
  - `public.izzy_lead_activities`
  - `public.izzy_followups`
  - campos operativos extra en `public.izzy_leads` como `lead_status_code`, `priority`, `next_followup_at`, `next_followup_status` y `do_not_call`

Flujo operativo:

- `Guardar estado` puede actualizar estado, prioridad y próximo seguimiento.
- `Registrar llamada manual` crea un rastro en `izzy_lead_calls` y actividad en `izzy_lead_activities`.
- `Seguimiento manual` crea o reutiliza un follow-up pendiente en `izzy_followups`.
- El backend recalcula siempre el próximo follow-up pendiente real del lead para mantener consistentes `izzy_leads.next_followup_at` y `izzy_leads.next_action`.

## Probar Local o Staging

No tocar producción. Trabaja con project ref de staging usando `?projectRef=...` o `IZZY_TEST_PROJECT_REF`.

- Instalar dependencias:

```bash
npm install
```

- Smoke general del portal:

```bash
npm run test:e2e
```

- Smoke específico de Call Center en staging:

```bash
IZZY_TEST_PROJECT_REF=tu_project_ref_staging \
IZZY_TEST_PIN=tu_pin \
IZZY_TEST_PASSWORD=tu_password \
IZZY_TEST_CALL_CENTER_LEAD_QUERY="lead estable staging" \
npx playwright test tests/e2e/call-center.spec.js --project=chromium
```

Notas para el smoke de Call Center:

- Usa un lead estable de staging, visible para la cuenta de prueba.
- Idealmente ese lead no debe tener follow-ups pendientes previos para que la recalculación del “próximo” sea determinista.
- El test crea dos follow-ups, valida que el primero quede como próximo y luego que al completarlo el lead salte al segundo.

## Secrets requeridos

Configura estos secrets antes de desplegar las funciones:

- `SUPABASE_SERVICE_ROLE_KEY`
- `IZZY_SESSION_SECRET`
- `IZZY_USERS_JSON`
- `IZZY_QUOTERS_JSON`
- `IZZY_APP_URL`
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`
- `RESEND_FROM_NAME`

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
