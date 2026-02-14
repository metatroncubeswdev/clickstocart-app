import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CountryService {
  static String getCountryCode() {
  try {
    final locale = Intl.getCurrentLocale(); // e.g. en_IN, en_US
    debugPrint("📍 Current locale: $locale");

    final parts = locale.split('_');
    if (parts.length > 1) {
      final country = parts[1].toUpperCase();
      debugPrint("🌍 Detected country: $country");
      return country;
    }
  } catch (e) {
    debugPrint("❌ Locale error: $e");
  }
  return 'US';
}


  // ✅ Only US / CA, fallback to US
  static String detectSupportedCountry() {
    final country = getCountryCode();
    if (country == 'US' || country == 'CA') {
      return country;
    }
    return 'IN';
  }
}
