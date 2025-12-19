-- =====================================================
-- FIX RIDE HISTORY STRUCTURE
-- Date: November 28, 2025
-- Purpose: Ensure ride_history has all needed columns
-- =====================================================

-- 1. Add missing columns if they don't exist
ALTER TABLE ride_history 
ADD COLUMN IF NOT EXISTS booking_id UUID,
ADD COLUMN IF NOT EXISTS from_location TEXT,
ADD COLUMN IF NOT EXISTS to_location TEXT,
ADD COLUMN IF NOT EXISTS fare_amount DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS driver_name TEXT,
ADD COLUMN IF NOT EXISTS driver_avatar_url TEXT,
ADD COLUMN IF NOT EXISTS vehicle_plate TEXT,
ADD COLUMN IF NOT EXISTS vehicle_model TEXT,
ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'pending',
ADD COLUMN IF NOT EXISTS payment_method TEXT,
ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- 2. Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_ride_history_passenger_completed 
ON ride_history(passenger_id, completed_at DESC);

-- 3. Create index for booking_id (to prevent duplicates)
CREATE UNIQUE INDEX IF NOT EXISTS idx_ride_history_booking_unique 
ON ride_history(booking_id) 
WHERE booking_id IS NOT NULL;

-- 4. Success message
DO $$
BEGIN
    RAISE NOTICE '✅ Ride history structure updated!';
    RAISE NOTICE '✅ All columns added!';
    RAISE NOTICE '✅ Indexes created for performance!';
    RAISE NOTICE '📱 Passenger reports will now show real data!';
END $$;

