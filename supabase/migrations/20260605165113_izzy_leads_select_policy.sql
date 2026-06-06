
CREATE POLICY "allow_anon_select"
  ON izzy_leads
  FOR SELECT
  TO anon
  USING (true);
;
