
ALTER TABLE izzy_leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_anon_insert"
  ON izzy_leads
  FOR INSERT
  TO anon
  WITH CHECK (true);
;
