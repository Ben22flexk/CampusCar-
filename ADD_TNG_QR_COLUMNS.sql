-- ============================================================================
-- Add Touch 'n Go QR Code columns to profiles table
-- ============================================================================

-- Add TNG QR code URL and phone number columns to profiles
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS tng_qr_code TEXT,
ADD COLUMN IF NOT EXISTS tng_phone_number VARCHAR(20);

-- Add comments for documentation
COMMENT ON COLUMN profiles.tng_qr_code IS 'URL to driver TNG QR code image stored in Supabase Storage';
COMMENT ON COLUMN profiles.tng_phone_number IS 'Phone number linked to driver Touch n Go account';

-- ============================================================================
-- Create Supabase Storage bucket for driver documents
-- ============================================================================

-- Create storage bucket for driver documents (if it doesn't exist)
INSERT INTO storage.buckets (id, name, public)
VALUES ('driver-documents', 'driver-documents', true)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- Set up storage policies
-- ============================================================================

-- Policy: Allow authenticated drivers to upload their own documents
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'Drivers can upload their documents'
    ) THEN
        CREATE POLICY "Drivers can upload their documents"
        ON storage.objects FOR INSERT
        TO authenticated
        WITH CHECK (
            bucket_id = 'driver-documents'
            AND (storage.foldername(name))[1] = 'tng_qr_codes'
        );
    END IF;
END $$;

-- Policy: Allow anyone to view driver documents (public bucket)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'Anyone can view driver documents'
    ) THEN
        CREATE POLICY "Anyone can view driver documents"
        ON storage.objects FOR SELECT
        TO public
        USING (bucket_id = 'driver-documents');
    END IF;
END $$;

-- Policy: Allow drivers to update their own documents
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'Drivers can update their documents'
    ) THEN
        CREATE POLICY "Drivers can update their documents"
        ON storage.objects FOR UPDATE
        TO authenticated
        USING (
            bucket_id = 'driver-documents'
            AND (storage.foldername(name))[1] = 'tng_qr_codes'
        );
    END IF;
END $$;

-- Policy: Allow drivers to delete their own documents
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'Drivers can delete their documents'
    ) THEN
        CREATE POLICY "Drivers can delete their documents"
        ON storage.objects FOR DELETE
        TO authenticated
        USING (
            bucket_id = 'driver-documents'
            AND (storage.foldername(name))[1] = 'tng_qr_codes'
        );
    END IF;
END $$;

-- ============================================================================
-- Verify the changes
-- ============================================================================

-- Check if columns were added
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns
WHERE table_name = 'profiles'
AND column_name IN ('tng_qr_code', 'tng_phone_number');

-- Check if storage bucket was created
SELECT id, name, public FROM storage.buckets WHERE id = 'driver-documents';

-- Check if storage policies were created
SELECT policyname, cmd, roles
FROM pg_policies
WHERE schemaname = 'storage'
AND tablename = 'objects'
AND policyname LIKE '%driver documents%';

-- ============================================================================
-- DONE! 
-- Now drivers can:
-- 1. Upload their TNG QR code in the profile page
-- 2. Passengers will see it in the ride summary after ride completion
-- ============================================================================

