create unique index if not exists mk_messages_campaign_phone_unique
  on public.mk_messages (campaign_id, telefono);
