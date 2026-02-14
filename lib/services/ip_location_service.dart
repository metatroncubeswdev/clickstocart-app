import 'dart:convert';
import 'package:http/http.dart' as http;

class IpLocationService {
  static Future<String> getCountryCode() async {
    try {
      final response = await http.get(
        Uri.parse('https://ipapi.co/json/'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final country = data['country_code'];

        if (country == 'US' || country == 'CA') {
          return country;
        }
      }
    } catch (_) {}

    return 'US'; // fallback
  }
}
