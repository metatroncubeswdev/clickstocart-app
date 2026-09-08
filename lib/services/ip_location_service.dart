import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Detects which storefront (US/CA) to default to on first launch, based on
/// the device's actual IP geolocation — not saved anywhere by this service
/// itself, just a one-shot lookup for whoever calls it to persist.
///
/// Uses Cloudflare's public edge-trace endpoint rather than a dedicated
/// geo-IP API: it's free, effectively unlimited (every Cloudflare edge
/// request already computes this), and needs no API key — unlike ipapi.co,
/// which rate-limited (HTTP 429) after repeated lookups during testing and
/// would be a real risk at any real install volume too.
class IpLocationService {
  static Future<String> getCountryCode() async {
    try {
      final response = await http
          .get(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final locLine = response.body.split('\n').firstWhere(
              (line) => line.startsWith('loc='),
              orElse: () => '',
            );
        final country = locLine.replaceFirst('loc=', '').trim();
        debugPrint("IpLocationService: detected country '$country'");

        if (country == 'US' || country == 'CA') {
          return country;
        }
      } else {
        debugPrint("IpLocationService: HTTP ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("IpLocationService: lookup failed — $e");
    }

    return 'US'; // fallback: no network yet, lookup failed, or outside US/CA
  }
}
