-- =====================================================
-- FIX DELETE RIDE FUNCTION
-- Date: November 29, 2025
-- Purpose: Create function to safely delete rides and bookings
-- =====================================================

-- 1. Create function to delete all bookings for a ride
CREATE OR REPLACE FUNCTION delete_ride_bookings(p_ride_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Delete all bookings associated with the ride
  DELETE FROM bookings WHERE ride_id = p_ride_id;
  
  RAISE NOTICE 'Deleted all bookings for ride %', p_ride_id;
END;
$$;

-- 2. Create function to safely delete a ride with all dependencies
CREATE OR REPLACE FUNCTION delete_ride_safely(p_ride_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_bookings_count INTEGER;
  v_result jsonb;
BEGIN
  -- Count bookings
  SELECT COUNT(*) INTO v_bookings_count
  FROM bookings
  WHERE ride_id = p_ride_id;
  
  -- Delete all bookings first
  DELETE FROM bookings WHERE ride_id = p_ride_id;
  
  -- Delete the ride
  DELETE FROM rides WHERE id = p_ride_id;
  
  -- Return result
  v_result := jsonb_build_object(
    'success', true,
    'bookings_deleted', v_bookings_count,
    'message', 'Ride deleted successfully'
  );
  
  RETURN v_result;
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM,
      'message', 'Failed to delete ride'
    );
END;
$$;

-- 3. Grant execute permissions
GRANT EXECUTE ON FUNCTION delete_ride_bookings(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_ride_safely(UUID) TO authenticated;

-- 4. Test message
DO $$
BEGIN
  RAISE NOTICE '✅ Delete ride functions created successfully!';
  RAISE NOTICE '📝 Function: delete_ride_bookings(p_ride_id UUID)';
  RAISE NOTICE '📝 Function: delete_ride_safely(p_ride_id UUID)';
  RAISE NOTICE '🔒 Permissions granted to authenticated users';
END $$;

