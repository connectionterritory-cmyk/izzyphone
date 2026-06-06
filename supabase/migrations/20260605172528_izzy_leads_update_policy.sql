
CREATE POLICY "allow_anon_update"
  ON izzy_leads
  FOR UPDATE
  TO anon
  USING (true)
  WITH CHECK (true);
;
