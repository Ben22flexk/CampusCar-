-- ============================================================================
-- Add Gender and Safety Features to CampusCar
-- ============================================================================
-- This script adds:
-- 1. Gender fields for users
-- 2. Gender preferences for matching
-- 3. Emergency contact information
-- 4. SOS/emergency tracking support
-- ============================================================================

-- ============================================================================
-- 1. Add Gender and Preference Fields to Profiles
-- ============================================================================

-- Add gender field (male, female, non_binary, prefer_not_to_say)
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS gender VARCHAR(20) CHECK (gender IN ('male', 'female', 'non_binary', 'prefer_not_to_say'));

-- Add passenger gender preference (female_only, same_gender_only, no_preference)
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS passenger_gender_preference VARCHAR(30) 
  DEFAULT 'no_preference' 
  CHECK (passenger_gender_preference IN ('female_only', 'same_gender_only', 'no_preference'));

-- Add driver gender preference (women_non_binary_only, no_preference)
-- For drivers: can choose to accept only women/non-binary passengers
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS driver_gender_preference VARCHAR(30) 
  DEFAULT 'no_preference' 
  CHECK (driver_gender_preference IN ('women_non_binary_only', 'no_preference'));

-- Add emergency contact fields
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS emergency_contact_name VARCHAR(100),
ADD COLUMN IF NOT EXISTS emergency_contact_phone VARCHAR(20),
ADD COLUMN IF NOT EXISTS emergency_contact_relationship VARCHAR(50);

-- Add campus security contact (can be set per user or use default)
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS campus_security_phone VARCHAR(20) DEFAULT '+60123456789';

-- Add comments for documentation
COMMENT ON COLUMN profiles.gender IS 'User gender: male, female, non_binary, prefer_not_to_say';
COMMENT ON COLUMN profiles.passenger_gender_preference IS 'Passenger preference: female_only, same_gender_only, no_preference';
COMMENT ON COLUMN profiles.driver_gender_preference IS 'Driver preference: women_non_binary_only, no_preference';
COMMENT ON COLUMN profiles.emergency_contact_name IS 'Name of emergency contact person';
COMMENT ON COLUMN profiles.emergency_contact_phone IS 'Phone number of emergency contact';
COMMENT ON COLUMN profiles.emergency_contact_relationship IS 'Relationship to user (e.g., parent, sibling, friend)';

-- ============================================================================
-- 2. Create SOS/Emergency Tracking Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS sos_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  ride_id UUID REFERENCES rides(id) ON DELETE SET NULL,
  booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
  triggered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  location_lat DOUBLE PRECISION,
  location_lng DOUBLE PRECISION,
  location_address TEXT,
  vehicle_plate_number TEXT,
  driver_details JSONB,
  status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'resolved', 'cancelled')),
  resolved_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_sos_events_user_id ON sos_events(user_id);
CREATE INDEX IF NOT EXISTS idx_sos_events_ride_id ON sos_events(ride_id);
CREATE INDEX IF NOT EXISTS idx_sos_events_status ON sos_events(status);
CREATE INDEX IF NOT EXISTS idx_sos_events_triggered_at ON sos_events(triggered_at DESC);

-- Add RLS policies for sos_events
ALTER TABLE sos_events ENABLE ROW LEVEL SECURITY;

-- Users can view their own SOS events
CREATE POLICY "Users can view their own SOS events"
ON sos_events FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Users can create their own SOS events
CREATE POLICY "Users can create their own SOS events"
ON sos_events FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Users can update their own active SOS events
CREATE POLICY "Users can update their own SOS events"
ON sos_events FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- 3. Create Trip Sharing Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS trip_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  share_token VARCHAR(100) UNIQUE NOT NULL,
  created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  shared_with_name VARCHAR(100),
  shared_with_phone VARCHAR(20),
  expires_at TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_trip_shares_booking_id ON trip_shares(booking_id);
CREATE INDEX IF NOT EXISTS idx_trip_shares_token ON trip_shares(share_token);
CREATE INDEX IF NOT EXISTS idx_trip_shares_created_by ON trip_shares(created_by);

-- Add RLS policies for trip_shares
ALTER TABLE trip_shares ENABLE ROW LEVEL SECURITY;

-- Users can view their own trip shares
CREATE POLICY "Users can view their own trip shares"
ON trip_shares FOR SELECT
TO authenticated
USING (auth.uid() = created_by);

-- Users can create their own trip shares
CREATE POLICY "Users can create their own trip shares"
ON trip_shares FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = created_by);

-- Anyone with the token can view trip share (for sharing links)
-- Note: This requires a function to validate tokens
CREATE POLICY "Anyone can view active trip shares by token"
ON trip_shares FOR SELECT
TO authenticated
USING (is_active = true AND expires_at > NOW());

-- ============================================================================
-- 4. Create Function to Generate Share Token
-- ============================================================================

CREATE OR REPLACE FUNCTION generate_trip_share_token()
RETURNS VARCHAR(100) AS $$
DECLARE
  token VARCHAR(100);
BEGIN
  -- Generate a secure random token
  token := encode(gen_random_bytes(32), 'base64');
  -- Remove special characters and limit length
  token := regexp_replace(token, '[^a-zA-Z0-9]', '', 'g');
  token := substring(token FROM 1 FOR 50);
  RETURN token;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. Create Function to Trigger SOS Event
-- ============================================================================

CREATE OR REPLACE FUNCTION trigger_sos_event(
  p_ride_id UUID DEFAULT NULL,
  p_booking_id UUID DEFAULT NULL,
  p_location_lat DOUBLE PRECISION DEFAULT NULL,
  p_location_lng DOUBLE PRECISION DEFAULT NULL,
  p_location_address TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  v_user_id UUID;
  v_sos_id UUID;
  v_vehicle_plate TEXT;
  v_driver_details JSONB;
BEGIN
  -- Get current user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  -- Get vehicle and driver details if ride_id is provided
  IF p_ride_id IS NOT NULL THEN
    SELECT 
      dv.vehicle_plate_number,
      jsonb_build_object(
        'driver_id', r.driver_id,
        'driver_name', p.full_name,
        'vehicle_model', dv.vehicle_model,
        'vehicle_color', dv.vehicle_color,
        'vehicle_plate', dv.vehicle_plate_number
      )
    INTO v_vehicle_plate, v_driver_details
    FROM rides r
    LEFT JOIN profiles p ON r.driver_id = p.id
    LEFT JOIN driver_verifications dv ON r.driver_id = dv.user_id
    WHERE r.id = p_ride_id;
  END IF;

  -- Create SOS event
  INSERT INTO sos_events (
    user_id,
    ride_id,
    booking_id,
    location_lat,
    location_lng,
    location_address,
    vehicle_plate_number,
    driver_details,
    status
  ) VALUES (
    v_user_id,
    p_ride_id,
    p_booking_id,
    p_location_lat,
    p_location_lng,
    p_location_address,
    v_vehicle_plate,
    v_driver_details,
    'active'
  )
  RETURNING id INTO v_sos_id;

  RETURN v_sos_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 6. Create Function to Create Trip Share
-- ============================================================================

CREATE OR REPLACE FUNCTION create_trip_share(
  p_booking_id UUID,
  p_shared_with_name VARCHAR(100) DEFAULT NULL,
  p_shared_with_phone VARCHAR(20) DEFAULT NULL,
  p_hours_valid INTEGER DEFAULT 24
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_share_token VARCHAR(100);
  v_share_id UUID;
  v_result JSONB;
BEGIN
  -- Get current user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  -- Verify user owns the booking
  IF NOT EXISTS (
    SELECT 1 FROM bookings 
    WHERE id = p_booking_id AND passenger_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Booking not found or access denied';
  END IF;

  -- Generate unique token
  LOOP
    v_share_token := generate_trip_share_token();
    EXIT WHEN NOT EXISTS (SELECT 1 FROM trip_shares WHERE share_token = v_share_token);
  END LOOP;

  -- Create trip share
  INSERT INTO trip_shares (
    booking_id,
    share_token,
    created_by,
    shared_with_name,
    shared_with_phone,
    expires_at
  ) VALUES (
    p_booking_id,
    v_share_token,
    v_user_id,
    p_shared_with_name,
    p_shared_with_phone,
    NOW() + (p_hours_valid || INTERVAL '1 hour')
  )
  RETURNING id INTO v_share_id;

  -- Return result with share link
  v_result := jsonb_build_object(
    'success', true,
    'share_id', v_share_id,
    'share_token', v_share_token,
    'expires_at', NOW() + (p_hours_valid || INTERVAL '1 hour')
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 7. Add Updated At Trigger for sos_events
-- ============================================================================

CREATE OR REPLACE FUNCTION update_sos_events_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_sos_events_updated_at
BEFORE UPDATE ON sos_events
FOR EACH ROW
EXECUTE FUNCTION update_sos_events_updated_at();

-- ============================================================================
-- 8. Add Updated At Trigger for trip_shares
-- ============================================================================

CREATE OR REPLACE FUNCTION update_trip_shares_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_trip_shares_updated_at
BEFORE UPDATE ON trip_shares
FOR EACH ROW
EXECUTE FUNCTION update_trip_shares_updated_at();

-- ============================================================================
-- 9. Create View for Active Trip Shares with Ride Info
-- ============================================================================

CREATE OR REPLACE VIEW active_trip_shares_view AS
SELECT 
  ts.id,
  ts.booking_id,
  ts.share_token,
  ts.created_by,
  ts.shared_with_name,
  ts.shared_with_phone,
  ts.expires_at,
  ts.created_at,
  b.ride_id,
  b.passenger_id,
  r.from_location,
  r.to_location,
  r.scheduled_time,
  r.ride_status,
  p.full_name as passenger_name,
  p.phone_number as passenger_phone
FROM trip_shares ts
JOIN bookings b ON ts.booking_id = b.id
JOIN rides r ON b.ride_id = r.id
JOIN profiles p ON b.passenger_id = p.id
WHERE ts.is_active = true 
  AND ts.expires_at > NOW();

-- ============================================================================
-- COMPLETION MESSAGE
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Gender and Safety Features added successfully!';
  RAISE NOTICE '';
  RAISE NOTICE 'Added columns to profiles:';
  RAISE NOTICE '  - gender';
  RAISE NOTICE '  - passenger_gender_preference';
  RAISE NOTICE '  - driver_gender_preference';
  RAISE NOTICE '  - emergency_contact_name';
  RAISE NOTICE '  - emergency_contact_phone';
  RAISE NOTICE '  - emergency_contact_relationship';
  RAISE NOTICE '  - campus_security_phone';
  RAISE NOTICE '';
  RAISE NOTICE 'Created tables:';
  RAISE NOTICE '  - sos_events (for emergency tracking)';
  RAISE NOTICE '  - trip_shares (for trip sharing)';
  RAISE NOTICE '';
  RAISE NOTICE 'Created functions:';
  RAISE NOTICE '  - trigger_sos_event()';
  RAISE NOTICE '  - create_trip_share()';
  RAISE NOTICE '  - generate_trip_share_token()';
END $$;
