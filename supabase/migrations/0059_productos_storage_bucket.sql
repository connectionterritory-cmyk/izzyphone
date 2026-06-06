-- Create the bucket explicitly if it doesn't already exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('productos', 'productos', true)
ON CONFLICT (id) DO NOTHING;
-- NOTE: storage.objects RLS is managed by Supabase — ALTER TABLE not needed (would require owner rights).

-- 1. SELECT Público: Cualquier persona / cliente no logueado puede ver las imágenes en el catálogo.
CREATE POLICY "Imágenes de productos son públicas"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'productos');
-- 2. INSERT / UPDATE / DELETE restringido a admin y distribuidores.
CREATE POLICY "Admins y Distribuidores pueden subir imágenes"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'productos' AND 
  (public.is_admin() OR public.is_distribuidor())
);
CREATE POLICY "Admins y Distribuidores pueden modificar imágenes"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'productos' AND 
  (public.is_admin() OR public.is_distribuidor())
);
CREATE POLICY "Admins y Distribuidores pueden eliminar imágenes"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'productos' AND 
  (public.is_admin() OR public.is_distribuidor())
);
