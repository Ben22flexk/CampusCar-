# CampusCar - Student Carpooling App

A full-featured carpooling application for TARC students with separate driver and passenger apps.

## 📱 Apps

### Driver App (`carpooling_driver/`)
- Create and manage rides
- View ride requests and bookings
- Real-time GPS tracking
- Earnings reports (daily, weekly, monthly)
- Profile management with TNG QR payment
- Push notifications

### Passenger App (`carpooling_main/`)
- Find and book rides
- Smart matching algorithm
- Live ride tracking
- Payment system (Cash/TNG)
- Ride history and reports
- Driver ratings

## 🗄️ Database Setup

### Critical SQL Scripts (Must Run First!)

#### 1. Fix Database Triggers (CRITICAL - Run This First!)
**File:** `FIX_DATABASE_TRIGGER_ISSUE.sql`
- Removes problematic triggers causing "Failed to notify passengers" error
- Makes ride_history columns nullable
- Fixes driver app completing rides
- **⚠️ RUN THIS FIRST to fix the error you're seeing!**

#### 2. Fix Ride History Structure (CRITICAL - Run This Second!)
**File:** `FIX_RIDE_HISTORY_STRUCTURE.sql`
- Adds all necessary columns to ride_history table
- Creates indexes for better performance
- Enables passenger reports to show real data
- **⚠️ RUN THIS AFTER script #1!**

### Optional SQL Scripts (For Enhanced Features)

#### 4. Profile Pictures Storage
**File:** `CREATE_PROFILE_PICTURES_BUCKET.sql`
- Creates Supabase storage bucket for profile pictures
- Sets up RLS policies
- Adds `avatar_url` column to profiles table
- **Optional: Only if you want profile picture upload**

#### 5. TNG Payment QR Codes
**File:** `ADD_TNG_QR_COLUMNS.sql`
- Adds TNG payment fields to profiles
- Creates storage bucket for driver payment QR codes
- Sets up RLS policies
- **Optional: Only if you want TNG QR payment feature**

**Note:** App works without optional scripts, but you'll miss profile pictures and TNG QR features.

## 🚀 Installation

### Prerequisites
- Flutter SDK (3.9.2 or higher)
- Supabase project
- Firebase project (for push notifications)

### Setup

1. **Clone the repository**
```bash
git clone <repository-url>
cd FYP
```

2. **Install dependencies**
```bash
# Driver App
cd carpooling_driver
flutter pub get

# Passenger App
cd ../carpooling_main
flutter pub get
```

3. **Configure Supabase**
- Create a Supabase project
- Run the SQL scripts **IN ORDER:**
  1. ⚠️ `FIX_DATABASE_TRIGGER_ISSUE.sql` (Critical - Fixes driver completion)
  2. ⚠️ `FIX_RIDE_HISTORY_STRUCTURE.sql` (Critical - Fixes reports)
  3. ✅ `CREATE_PROFILE_PICTURES_BUCKET.sql` (Optional - Profile pictures)
  4. ✅ `ADD_TNG_QR_COLUMNS.sql` (Optional - TNG QR payment)
- Update Supabase credentials in both apps
- **Note:** The duplicate key error has been fixed in the code (no SQL script needed)

4. **Configure Firebase**
- Create Firebase projects for both apps
- Add `google-services.json` to:
  - `carpooling_driver/android/app/`
  - `carpooling_main/android/app/`

5. **Run the apps**
```bash
# Driver App
cd carpooling_driver
flutter run

# Passenger App
cd carpooling_main
flutter run
```

## 📦 Key Features

### Driver Features
- ✅ Ride creation with route planning
- ✅ Smart matching with passengers
- ✅ Real-time GPS tracking
- ✅ Earnings dashboard
- ✅ Summary reports (daily/weekly/monthly)
- ✅ PDF export for reports
- ✅ TNG QR code payment
- ✅ Profile picture upload
- ✅ Push notifications
- ✅ Driver ratings

### Passenger Features
- ✅ Smart ride matching
- ✅ Real-time ride tracking
- ✅ Booking management
- ✅ Payment system (Cash/TNG)
- ✅ Ride history
- ✅ Summary reports (daily/weekly/monthly)
- ✅ PDF export for reports
- ✅ Profile picture upload
- ✅ Driver rating system
- ✅ Push notifications

## 🛠️ Technology Stack

### Frontend
- **Flutter** - Cross-platform mobile framework
- **Dart** - Programming language
- **Riverpod** - State management
- **Flutter Hooks** - Widget lifecycle management

### Backend
- **Supabase** - Backend as a Service
  - PostgreSQL database
  - Real-time subscriptions
  - Storage for files
  - Authentication
- **Firebase Cloud Messaging** - Push notifications

### Maps & Location
- **Flutter Map** - Map display
- **Geolocator** - GPS tracking
- **Geocoding** - Address to coordinates

### Reports & Charts
- **PDF** - PDF generation
- **Printing** - PDF export
- **FL Chart** - Data visualization

## 📊 Database Schema

### Main Tables
- `profiles` - User profiles (drivers and passengers)
- `rides` - Ride listings
- `bookings` - Ride bookings/requests
- `ride_history` - Completed rides
- `driver_verifications` - Driver vehicle details
- `driver_ratings` - Driver rating system
- `notifications` - Push notification records

### Storage Buckets
- `profile-pictures` - User avatars
- `driver-documents` - Driver TNG QR codes

## 🔐 Security

- Row Level Security (RLS) enabled on all tables
- Users can only access their own data
- Authenticated users required for all operations
- Storage policies for file access control

## 📱 Push Notifications

Implemented for:
- Ride request approval
- Driver arrival notifications
- Ride completion
- Payment reminders

## 🧪 Testing

### Driver App
1. Register as driver
2. Complete driver verification
3. Create a ride
4. Accept passenger requests
5. Start ride and track
6. Complete ride
7. View earnings reports

### Passenger App
1. Register as passenger
2. Search for rides
3. Book a ride
4. Track driver
5. Complete payment
6. Rate driver
7. View ride history

## 📝 Notes

- This is a student project for TARC
- Uses Supabase for backend services
- Implements real-time features using Supabase Realtime
- All monetary values in Malaysian Ringgit (RM)
- Phone numbers use Malaysian format (+60)

## 🐛 Known Issues

None currently. All major issues have been resolved.

## 📄 License

This project is for educational purposes as part of Final Year Project at TARC.

## 👥 Support

For issues or questions, please check the documentation or contact the development team.

---

**Last Updated:** November 27, 2025

