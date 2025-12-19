-- =====================================================
-- FIX FOREIGN KEY CASCADE FOR RIDE DELETION
-- Date: December 1, 2025
-- Purpose: Fix foreign key constraint to allow cascade deletion
-- =====================================================

-- This error occurs because the foreign key is set to SET NULL on delete,
-- but ride_id is NOT NULL, creating a conflict.
-- Solution: Change foreign key to CASCADE DELETE

-- 1. First, find and drop the existing foreign key constraint
DO $$
DECLARE
    constraint_name text;
BEGIN
    -- Find the constraint name for ride_id in bookings table
    SELECT conname INTO constraint_name
    FROM pg_constraint
    WHERE conrelid = 'bookings'::regclass
    AND contype = 'f'
    AND conkey = (SELECT array_agg(attnum) FROM pg_attribute 
                  WHERE attrelid = 'bookings'::regclass 
                  AND attname = 'ride_id');
    
    IF constraint_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE bookings DROP CONSTRAINT IF EXISTS %I', constraint_name);
        RAISE NOTICE '✅ Dropped old constraint: %', constraint_name;
    END IF;
END $$;

-- 2. Add new foreign key constraint with CASCADE DELETE
ALTER TABLE bookings
ADD CONSTRAINT bookings_ride_id_fkey 
FOREIGN KEY (ride_id) 
REFERENCES rides(id) 
ON DELETE CASCADE;

-- 3. Verify the constraint
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM pg_constraint 
        WHERE conname = 'bookings_ride_id_fkey' 
        AND confdeltype = 'c' -- 'c' means CASCADE
    ) THEN
        RAISE NOTICE '✅ Foreign key constraint successfully updated with CASCADE DELETE';
    ELSE
        RAISE WARNING '⚠️ Failed to create CASCADE constraint';
    END IF;
END $$;

-- 4. Success message
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ FOREIGN KEY CASCADE FIX COMPLETED!';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Changes made:';
    RAISE NOTICE '  • Dropped old foreign key constraint';
    RAISE NOTICE '  • Created new constraint: bookings_ride_id_fkey';
    RAISE NOTICE '  • Set to CASCADE DELETE';
    RAISE NOTICE '';
    RAISE NOTICE '✅ Now when a ride is deleted:';
    RAISE NOTICE '  → All related bookings will be automatically deleted';
    RAISE NOTICE '  → No more "null value in ride_id" errors';
    RAISE NOTICE '';
    RAISE NOTICE '🧪 Test by deleting a ride from the driver app';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

