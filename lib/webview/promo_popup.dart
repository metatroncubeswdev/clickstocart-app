import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A small popup showing an offers/promo page that marketing edits directly
/// in Odoo's normal website page builder — no custom backend needed.
/// Whether this appears at all is controlled by that page's own
/// Published/Unpublished toggle in Odoo (checked before this widget is ever
/// opened — see `_maybeShowPromo` in webview_screen.dart).
class PromoPopup extends StatefulWidget {
  const PromoPopup({super.key, required this.url});

  final String url;

  @override
  State<PromoPopup> createState() => _PromoPopupState();
}

class _PromoPopupState extends State<PromoPopup> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.6,
              color: Colors.white,
              child: WebViewWidget(controller: _controller),
            ),
          ),
          if (_loading)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  color: Colors.white,
                  child: const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFC8000)),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.4),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
