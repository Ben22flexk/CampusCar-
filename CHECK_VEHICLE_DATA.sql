-- Check vehicle data in driver_verifications table
-- Run this to see what vehicle data exists

-- 1. Check all driver verifications
SELECT 
    p.full_name,
    p.email,
    dv.vehicle_manufacturer,
    dv.vehicle_model,
    dv.vehicle_color,
    dv.vehicle_plate_number,
    dv.vehicle_year,
    dv.vehicle_seats,
    dv.verification_status
FROM driver_verifications dv
JOIN profiles p ON p.id = dv.user_id
ORDER BY p.full_name;

-- 2. Check for Tan Yih Jiun specifically
SELECT 
    p.full_name,
    p.email,
    dv.*
FROM driver_verifications dv
JOIN profiles p ON p.id = dv.user_id
WHERE p.full_name ILIKE '%Tan%Yih%Jiun%' 
   OR p.email ILIKE '%tan%';

-- 3. Check all columns in driver_verifications table
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'driver_verifications'
ORDER BY ordinal_position;

