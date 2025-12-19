/// Gender and preference enums for safer matching
enum Gender {
  male('male'),
  female('female'),
  nonBinary('non_binary'),
  preferNotToSay('prefer_not_to_say');

  final String value;
  const Gender(this.value);

  static Gender? fromString(String? value) {
    if (value == null) return null;
    return Gender.values.firstWhere(
      (e) => e.value == value,
      orElse: () => Gender.preferNotToSay,
    );
  }
}

/// Passenger gender preference for matching
enum PassengerGenderPreference {
  femaleOnly('female_only'),
  sameGenderOnly('same_gender_only'),
  noPreference('no_preference');

  final String value;
  const PassengerGenderPreference(this.value);

  static PassengerGenderPreference? fromString(String? value) {
    if (value == null) return PassengerGenderPreference.noPreference;
    return PassengerGenderPreference.values.firstWhere(
      (e) => e.value == value,
      orElse: () => PassengerGenderPreference.noPreference,
    );
  }

  String get displayName {
    switch (this) {
      case PassengerGenderPreference.femaleOnly:
        return 'Female Driver Only';
      case PassengerGenderPreference.sameGenderOnly:
        return 'Same Gender Only';
      case PassengerGenderPreference.noPreference:
        return 'No Preference';
    }
  }
}

/// Driver gender preference for accepting passengers
enum DriverGenderPreference {
  womenNonBinaryOnly('women_non_binary_only'),
  noPreference('no_preference');

  final String value;
  const DriverGenderPreference(this.value);

  static DriverGenderPreference? fromString(String? value) {
    if (value == null) return DriverGenderPreference.noPreference;
    return DriverGenderPreference.values.firstWhere(
      (e) => e.value == value,
      orElse: () => DriverGenderPreference.noPreference,
    );
  }

  String get displayName {
    switch (this) {
      case DriverGenderPreference.womenNonBinaryOnly:
        return 'Women/Non-Binary Only';
      case DriverGenderPreference.noPreference:
        return 'No Preference';
    }
  }
}
