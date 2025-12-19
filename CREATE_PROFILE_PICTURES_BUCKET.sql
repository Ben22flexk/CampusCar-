-- =====================================================
-- CREATE PROFILE PICTURES STORAGE BUCKET
-- Date: November 27, 2025
-- Purpose: Create storage bucket for user profile pictures
-- =====================================================

-- 1. Create the storage bucket for profile pictures
INSERT INTO storage.buckets (id, name, public)
VALUES ('profile-pictures', 'profile-pictures', TRUE)
ON CONFLICT (id) DO NOTHING;

-- 2. RLS is already enabled on storage.objects by Supabase

-- 3. Drop existing policies if they exist (to avoid conflicts)
DROP POLICY IF EXISTS "Users can upload their own profile picture" ON storage.objects;
DROP POLICY IF EXISTS "Users can view their own profile picture" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own profile picture" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own profile picture" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view all profile pictures" ON storage.objects;

-- 4. Policy: Users can upload their own profile picture
CREATE POLICY "Users can upload their own profile picture"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'profile-pictures' AND
  (storage.foldername(name))[1]::uuid = auth.uid()
);

-- 5. Policy: Users can view their own profile picture
CREATE POLICY "Users can view their own profile picture"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'profile-pictures' AND
  (storage.foldername(name))[1]::uuid = auth.uid()
);

-- 6. Policy: Users can update their own profile picture
CREATE POLICY "Users can update their own profile picture"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'profile-pictures' AND
  (storage.foldername(name))[1]::uuid = auth.uid()
);

-- 7. Policy: Users can delete their own profile picture
CREATE POLICY "Users can delete their own profile picture"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'profile-pictures' AND
  (storage.foldername(name))[1]::uuid = auth.uid()
);

-- 8. Policy: Anyone can view profile pictures (for displaying in app)
CREATE POLICY "Anyone can view all profile pictures"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'profile-pictures');

-- 9. Update profiles table to ensure avatar_url column exists
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- 10. Add index for faster avatar lookups
CREATE INDEX IF NOT EXISTS idx_profiles_avatar_url ON profiles(avatar_url) WHERE avatar_url IS NOT NULL;

-- =====================================================
-- TESTING
-- =====================================================

-- Test bucket creation
SELECT * FROM storage.buckets WHERE id = 'profile-pictures';

-- Test policies
SELECT * FROM pg_policies WHERE tablename = 'objects' AND policyname LIKE '%profile%';

-- =====================================================
-- USAGE INSTRUCTIONS
-- =====================================================

/*
FOLDER STRUCTURE:
  profile-pictures/
    ├── {user_id_1}/
    │   └── avatar.jpg
    ├── {user_id_2}/
    │   └── avatar.png
    └── ...

UPLOAD PATH FORMAT:
  {user_id}/avatar.{extension}

EXAMPLE:
  "123e4567-e89b-12d3-a456-426614174000/avatar.jpg"

PUBLIC URL:
  https://{supabase_project}.supabase.co/storage/v1/object/public/profile-pictures/{user_id}/avatar.jpg
*/

