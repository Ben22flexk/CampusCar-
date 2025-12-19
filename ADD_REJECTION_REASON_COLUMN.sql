-- =====================================================
-- ADD REJECTION REASON COLUMN
-- Date: November 29, 2025
-- Purpose: Add rejection_reason column to bookings table
-- =====================================================

-- 1. Add rejection_reason column if it doesn't exist
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- 2. Add index for better query performance
CREATE INDEX IF NOT EXISTS idx_bookings_rejection_reason 
ON bookings(rejection_reason) 
WHERE rejection_reason IS NOT NULL;

-- 3. Add comment to column
COMMENT ON COLUMN bookings.rejection_reason IS 'Reason provided by driver when rejecting a booking request';

-- 4. Success message
DO $$
BEGIN
    RAISE NOTICE '✅ Rejection reason column added to bookings table!';
    RAISE NOTICE '📝 Column: rejection_reason (TEXT, nullable)';
    RAISE NOTICE '🔍 Index created for performance';
    RAISE NOTICE '📱 Drivers can now provide reasons when rejecting requests!';
END $$;

