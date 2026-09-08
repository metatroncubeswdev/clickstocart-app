import 'dart:convert';

import 'package:http/http.dart' as http;

/// A single row in the native search-suggestions dropdown — either a
/// matching product or a matching product category.
class ProductSuggestion {
  final String name;
  final String url;
  final String? imageUrl;
  final String? price;
  final bool isCategory;

  ProductSuggestion({
    required this.name,
    required this.url,
    required this.isCategory,
    this.imageUrl,
    this.price,
  });
}

/// Talks to Odoo's own site-search JSON-RPC endpoint
/// (`/website/snippet/autocomplete`) — the same one the website's header
/// search box uses — so suggestions match exactly what the live site would
/// show, with no separate backend needed.
class SearchService {
  static String _stripHtml(String value) {
    return value.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  static Future<List<ProductSuggestion>> suggestProducts({
    required String baseUrl,
    required String term,
    int limit = 6,
  }) async {
    if (term.trim().isEmpty) return [];

    try {
      final uri = Uri.parse(baseUrl).resolve("website/snippet/autocomplete");
      final response = await http
          .post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "jsonrpc": "2.0",
              "method": "call",
              "params": {
                "search_type": "products",
                "term": term,
                "order": "name asc",
                "limit": limit,
                "max_nb_chars": 40,
                "options": {
                  "displayImage": true,
                  "displayDescription": false,
                  "displayExtraLink": false,
                  "displayDetail": true,
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return [];

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final results = decoded["result"]?["results"] as List<dynamic>? ?? [];
      final baseUri = Uri.parse(baseUrl);

      return results
          .map((raw) {
            final item = raw as Map<String, dynamic>;
            final name = _stripHtml(item["name"] as String? ?? "");
            final imagePath = item["image_url"] as String?;
            final detail = item["detail"] as String?;

            return ProductSuggestion(
              name: name,
              url: (item["website_url"] as String?) ?? "/shop",
              isCategory: item["_fa"] == "fa-folder-o",
              imageUrl: imagePath != null ? baseUri.resolve(imagePath).toString() : null,
              price: (detail != null && detail.isNotEmpty) ? _stripHtml(detail) : null,
            );
          })
          .where((s) => s.name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
