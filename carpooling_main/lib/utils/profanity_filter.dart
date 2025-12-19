/// Malaysian Profanity Filter
/// Checks for vulgar words in Bahasa Melayu and English slang
class ProfanityFilter {
  // Malaysian vulgar words (Bahasa Melayu + English slang)
  static final List<String> _badWords = [
    // Bahasa Melayu vulgar words
    'puki',
    'pukimak',
    'babi',
    'anjing',
    'bodoh',
    'bangang',
    'sial',
    'celaka',
    'palui',
    'lancau',
    'kimak',
    'pundek',
    'butoh',
    'pantat',
    'jubor',
    'pepek',
    'memek',
    'kontol',
    'bangsat',
    'jancok',
    'goblok',
    'tolol',
    'bego',
    
    // English vulgar words
    'fuck',
    'shit',
    'bitch',
    'damn',
    'ass',
    'asshole',
    'bastard',
    'cunt',
    'dick',
    'cock',
    'pussy',
    'slut',
    'whore',
    
    // Add more as needed
  ];

  /// Check if text contains profanity
  static bool hasProfanity(String text) {
    if (text.trim().isEmpty) return false;
    
    final lowerText = text.toLowerCase();
    
    // Check each bad word
    for (final word in _badWords) {
      // Use word boundary regex to match whole words only
      final pattern = RegExp(r'\b' + word + r'\b', caseSensitive: false);
      if (pattern.hasMatch(lowerText)) {
        return true;
      }
    }
    
    return false;
  }

  /// Get the first profane word found (for debugging/logging)
  static String? getFirstProfaneWord(String text) {
    if (text.trim().isEmpty) return null;
    
    final lowerText = text.toLowerCase();
    
    for (final word in _badWords) {
      final pattern = RegExp(r'\b' + word + r'\b', caseSensitive: false);
      if (pattern.hasMatch(lowerText)) {
        return word;
      }
    }
    
    return null;
  }

  /// Clean text by replacing profanity with asterisks
  static String cleanText(String text) {
    if (text.trim().isEmpty) return text;
    
    var cleanedText = text;
    
    for (final word in _badWords) {
      final pattern = RegExp(r'\b' + word + r'\b', caseSensitive: false);
      cleanedText = cleanedText.replaceAllMapped(
        pattern,
        (match) => '*' * match.group(0)!.length,
      );
    }
    
    return cleanedText;
  }
}

