import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import '../services/ip_location_service.dart';
import '../services/push_notification_service.dart';
import '../services/search_service.dart';
import 'js_scripts.dart';
import 'offline_view.dart';
import 'promo_popup.dart';

class WebViewWithNav extends StatefulWidget {
  const WebViewWithNav({super.key});

  @override
  State<WebViewWithNav> createState() => _WebViewWithNavState();
}

class _WebViewWithNavState extends State<WebViewWithNav> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _currentIndex = 0;
  bool _isNavigating = true; // Start with loader active
  bool _isFirstLoad = true; // Only the cold start gets the full branded overlay
  double _loadingProgress = 0;
  String _currentPath = "/";
  String _cartCount = "0";

  // Offline / load-error handling
  bool _isOffline = false;
  bool _hasLoadError = false;
  String? _httpErrorDetail;
  String? _loadingUrl;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Pull-to-refresh
  double _webScrollY = 0;
  double _pullDistance = 0;
  bool _isRefreshing = false;
  static const double _pullTriggerDistance = 80;

  // Auth bridge
  bool _isLoggedIn = false;
  String? _userName;

  // In-app header nav (search + back), shown on every page
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _canGoBack = false;
  bool _searchFocused = false;
  List<ProductSuggestion> _suggestions = [];
  Timer? _searchDebounce;

  WebViewController? _controller;

  // ================= CONFIG =================
  static const String appParam = "1";

  String baseUrl = "https://clickstocartca.com/";
  String versionParam = "05c7c5a71e52";
  String _selectedCountry = "CA";
  // =========================================


  List<String> _bottomNavUrls = [];

  @override
  void initState() {
    super.initState();
    _loadSavedCountry();
    _loadPersistedAuth();
    _initConnectivity();
    _searchFocusNode.addListener(() {
      setState(() => _searchFocused = _searchFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    final initial = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() => _isOffline = initial.every((r) => r == ConnectivityResult.none));
    }

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (!mounted || offline == _isOffline) return;

      setState(() => _isOffline = offline);
      if (!offline && _hasLoadError) {
        _retryLoad();
      }
    });
  }

  Future<void> _loadPersistedAuth() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = prefs.getBool("isLoggedIn") ?? false;
      _userName = prefs.getString("userName");
    });
  }

  /// Only geo-detects on a genuinely first launch (no saved preference) —
  /// once a country is set, later launches always respect it as-is, even
  /// if the device's location changes (e.g. travel).
  Future<void> _loadSavedCountry() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString("country");

    final country = saved ?? await IpLocationService.getCountryCode();
    if (saved == null) {
      await prefs.setString("country", country);
    }

    _applyCountry(country, reload: false);
    _initWebView();
  }

  Future<void> _applyCountry(String country, {bool reload = true}) async {
    if (country == "CA") {
      baseUrl = "https://clickstocartca.com/";
      versionParam = "05c7c5a71e52";
    } else {
      baseUrl = "https://clickstocartus.com/";
      versionParam = "bf1c4c815a09";
    }

    _selectedCountry = country;
    _rebuildBottomNavUrls();

    if (reload && _controller != null) {
      _controller!.loadRequest(Uri.parse(_bottomNavUrls.first));
    }
  }

  void _rebuildBottomNavUrls() {
    _bottomNavUrls = [
      "/",
      "/all-products/",
      "/shop/",
      "/shop/cart/",
      _isLoggedIn ? "/my/home" : "/web/login/",
    ].map(_buildUrl).toList();
  }

  /// Odoo page path the marketing team edits directly via the normal
  /// website page builder. Its own Published/Unpublished toggle in Odoo is
  /// the on/off switch for this whole feature — no custom backend needed.
  static const String _promoPath = "/mobile-offers";

  /// Shows the offers popup at most once per day, and only if that Odoo
  /// page is actually published (a plain GET returning 200) — so an
  /// unpublished/nonexistent page just silently shows nothing.
  Future<void> _maybeShowPromo() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateTime.now().toIso8601String().split('T').first;
    if (prefs.getString("lastPromoShownDate") == todayKey) return;

    final url = _buildUrl(_promoPath);
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;
    } catch (e) {
      debugPrint("Promo check failed: $e");
      return;
    }

    await prefs.setString("lastPromoShownDate", todayKey);
    if (!mounted) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => PromoPopup(url: url),
    );
  }

  void _retryLoad() {
    setState(() {
      _hasLoadError = false;
      _httpErrorDetail = null;
      _isNavigating = true;
    });
    _controller?.reload();
  }

  Future<void> _initWebView() async {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setBackgroundColor(Colors.white)
      // Was spoofing an iPhone Safari UA on Android too — confirmed via a
      // live CDP capture that this contradicts the browser's own Client
      // Hints (sec-ch-ua correctly says "Android WebView"/"Chromium" while
      // User-Agent claimed iPhone/Safari), which is exactly the mismatch a
      // WAF flags — the confirmed cause of the CA 500s (Chrome loads the
      // identical URL fine with its own honest UA). Explicitly overriding
      // to a real Android UA here, rather than just omitting the call,
      // since the platform WebView was observed still reporting the old
      // spoofed UA even after fully uninstalling and reinstalling.
      ..setUserAgent(
        Platform.isAndroid
            ? "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
            : null,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _loadingUrl = url;
            setState(() => _isNavigating = true);
          },
          onPageFinished: (url) {
            _syncBottomNavWithUrl(url);
            _injectCartCountObserver();
            _injectHideElements();
            _injectScrollObserver();
            _injectAuthCheck();
            _injectCookieConsent();
            _injectExternalLinkFix();

            final wasFirstLoad = _isFirstLoad;
            setState(() {
              _isNavigating = false;
              _isFirstLoad = false;
              // Only clear a previously-flagged HTTP error if this
              // successful finish is for that same page — a background
              // sub-resource finishing afterward shouldn't silently dismiss
              // a real main-frame error screen still on display.
              if (!_hasLoadError || url == _loadingUrl) {
                _hasLoadError = false;
                _httpErrorDetail = null;
              }
            });
            _controller!.canGoBack().then((can) {
              if (mounted) setState(() => _canGoBack = can);
            });

            if (wasFirstLoad) {
              _maybeShowPromo();
              PushNotificationService.instance.initialize(
                onNotificationTap: (path) {
                  _controller?.loadRequest(Uri.parse(_buildUrl(path)));
                },
              );
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
              Page resource error:
                code: ${error.errorCode}
                description: ${error.description}
                errorType: ${error.errorType}
                isForMainFrame: ${error.isForMainFrame}
            ''');

            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _hasLoadError = true;
                _isNavigating = false;
                _isFirstLoad = false;
              });
            }
          },
          onHttpError: (HttpResponseError error) {
            final status = error.response?.statusCode;
            final requestUri = error.request?.uri;
            debugPrint('HTTP error: $status for $requestUri');

            // HttpResponseError doesn't flag whether this was the main
            // page or just a sub-resource (image, script, ...), so infer
            // it by comparing against the URL we most recently navigated
            // to — only show the error screen when they match.
            final loadingUri = _loadingUrl != null ? Uri.tryParse(_loadingUrl!) : null;
            final isMainFrame = requestUri != null &&
                loadingUri != null &&
                requestUri.host == loadingUri.host &&
                requestUri.path == loadingUri.path;

            if (isMainFrame && status != null && status >= 400 && mounted) {
              setState(() {
                _hasLoadError = true;
                _isNavigating = false;
                _isFirstLoad = false;
                _httpErrorDetail = "HTTP $status — $requestUri";
              });
            }
          },
          onProgress: (int progress) {
            setState(() {
              _loadingProgress = progress / 100.0;
            });

            // 🚀 ULTRA-FAST STRATEGY:
            // 1. Inject hiding CSS + cookie consent as soon as the page
            // starts rendering (20%). This ensures the header is GONE, and
            // Odoo's cookie popup never has a chance to render, before the
            // user even sees it.
            if (progress > 20 && progress < 100) {
              _injectHideElements();
              _injectCookieConsent();
              _injectExternalLinkFix();
            }

            // 2. Dismiss loader early (at 85%)
            // Most pages are visually complete and interactable at 85%.
            if (progress >= 85) {
              _injectHideElements();
              _injectCartCountObserver();
              if (mounted && _isNavigating) {
                setState(() => _isNavigating = false);
              }
            }
          },
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri != null && _isExternalLink(uri)) {
              await _launchExternally(uri);
              return NavigationDecision.prevent;
            }

            final fixed = _ensureAppAndVersion(request.url);
            if (fixed != request.url) {
              _controller!.loadRequest(Uri.parse(fixed));
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..setOnConsoleMessage((message) {
        debugPrint("JS Console: ${message.message}");
      })
      ..addJavaScriptChannel(
        "CartCountChannel",
        onMessageReceived: (message) {
          debugPrint("CartCountChannel received: ${message.message}");
          if (mounted) {
            setState(() {
              _cartCount = message.message;
            });
          }
        },
      )
      ..addJavaScriptChannel(
        "ScrollChannel",
        onMessageReceived: (message) {
          _webScrollY = double.tryParse(message.message) ?? _webScrollY;
        },
      )
      ..addJavaScriptChannel(
        "AuthChannel",
        onMessageReceived: _handleAuthMessage,
      )
      ..loadRequest(Uri.parse(_bottomNavUrls.first));

    setState(() {}); // ensure rebuild after init
  }

  Future<void> _handleAuthMessage(JavaScriptMessage message) async {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final loggedIn = data["loggedIn"] == true;
      final name = data["name"] as String?;

      if (loggedIn == _isLoggedIn && name == _userName) return;

      if (mounted) {
        setState(() {
          _isLoggedIn = loggedIn;
          _userName = (name != null && name.isNotEmpty) ? name : null;
          _rebuildBottomNavUrls();
        });
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("isLoggedIn", loggedIn);
      if (_userName != null) {
        await prefs.setString("userName", _userName!);
      } else {
        await prefs.remove("userName");
      }
    } catch (e) {
      debugPrint("AuthChannel parse error: $e");
    }
  }

  Future<void> _logout() async {
    HapticFeedback.selectionClick();
    _scaffoldKey.currentState?.closeDrawer();

    await WebViewCookieManager().clearCookies();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("isLoggedIn", false);
    await prefs.remove("userName");

    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _userName = null;
      _currentIndex = 0;
      _isNavigating = true;
      _rebuildBottomNavUrls();
    });

    _controller?.loadRequest(Uri.parse(_buildUrl("/")));
  }

  String _ensureAppAndVersion(String url) {
    var uri = Uri.parse(url);

    // Only operate on our domains
    if (!uri.host.contains("clickstocart")) return url;

    // Force HTTPS (iOS blocks cleartext HTTP)
    if (uri.scheme == 'http') {
      uri = uri.replace(scheme: 'https');
    }

    // Ensure app & version params are present/updated
    final params = Map<String, String>.from(uri.queryParameters);
    params["app"] = appParam;
    params["v"] = versionParam;

    return uri.replace(queryParameters: params).toString();
  }

  String _buildUrl(String path) {
    // baseUrl always ends in "/" and every path always starts with "/" —
    // naive concatenation produced "https://host//path" on every single
    // request in the app, which is what was triggering the CA 500s.
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(
      "$normalizedBase$normalizedPath",
    ).replace(queryParameters: {"app": appParam, "v": versionParam}).toString();
  }

  void _changeTab(int index) {
    if (_currentIndex == index || _controller == null) return;

    HapticFeedback.selectionClick();

    setState(() {
      _currentIndex = index;
      _isNavigating = true;
    });

    _controller!.loadRequest(Uri.parse(_bottomNavUrls[index]));
  }

  /// Closes the drawer or goes back through webview history, in that order
  /// of priority. Returns whether it handled anything.
  Future<bool> _tryGoBack() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
      return true;
    }

    if (_controller != null && await _controller!.canGoBack()) {
      HapticFeedback.selectionClick();
      _controller!.goBack();
      return true;
    }

    return false;
  }

  void _performSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty || _controller == null) return;

    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();

    final shopUrl = Uri.parse(_buildUrl("/shop"));
    final params = Map<String, String>.from(shopUrl.queryParameters)..["search"] = trimmed;

    setState(() {
      _currentIndex = 2; // Shop tab is the closest match for search results
      _isNavigating = true;
      _suggestions = [];
    });

    _controller!.loadRequest(shopUrl.replace(queryParameters: params));
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await SearchService.suggestProducts(baseUrl: baseUrl, term: trimmed);
      if (mounted && _searchController.text.trim() == trimmed) {
        setState(() => _suggestions = results);
      }
    });
  }

  void _selectSuggestion(ProductSuggestion suggestion) {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();

    setState(() {
      _suggestions = [];
      _isNavigating = true;
    });

    _controller?.loadRequest(Uri.parse(_buildUrl(suggestion.url)));
  }

  /// Opens the phone dialer pre-filled with the support number for whichever
  /// storefront (US/CA) is currently active. Dialing itself always stays a
  /// user-confirmed action in the native Phone app, not something the app
  /// places automatically.
  Future<void> _callSupport() async {
    HapticFeedback.selectionClick();
    final number = _selectedCountry == "CA" ? "9054488003" : "7345643741";
    try {
      await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (e) {
      debugPrint("Could not open dialer: $e");
    }
  }

  /// True for anything that isn't part of the clickstocart site itself —
  /// WhatsApp, tel:/mailto: links, social media, etc. Those should open in
  /// their real native app, never attempt to render inside this webview.
  bool _isExternalLink(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return true;
    return !uri.host.contains('clickstocart');
  }

  /// Friendly name for the toast, e.g. "Opening WhatsApp…" — falls back to
  /// a generic message for anything not explicitly recognized.
  String _externalAppLabel(Uri uri) {
    final host = uri.host.toLowerCase();
    if (uri.scheme == 'tel') return 'Phone';
    if (uri.scheme == 'mailto') return 'Mail';
    if (uri.scheme == 'sms') return 'Messages';
    if (host.contains('wa.me') || host.contains('whatsapp')) return 'WhatsApp';
    if (host.contains('instagram')) return 'Instagram';
    if (host.contains('facebook') || host.contains('fb.com')) return 'Facebook';
    if (host.contains('youtube') || host.contains('youtu.be')) return 'YouTube';
    if (host.contains('twitter') || host.contains('x.com')) return 'X';
    if (host.contains('pinterest') || host.contains('pin.it')) return 'Pinterest';
    if (host.contains('tiktok')) return 'TikTok';
    return 'browser';
  }

  /// Action links (call/message/chat apps) hand off to the real app
  /// directly — that's what tapping them is for, no extra step wanted.
  /// Everything else (Instagram, Facebook, generic websites, ...) opens in
  /// an in-app browser sheet (Chrome Custom Tabs / SFSafariViewController)
  /// so it still feels like part of the app, with one tap back.
  bool _isActionLink(Uri uri) {
    const actionSchemes = {'tel', 'mailto', 'sms'};
    if (actionSchemes.contains(uri.scheme)) return true;
    final host = uri.host.toLowerCase();
    return host.contains('wa.me') || host.contains('whatsapp');
  }

  Future<void> _launchExternally(Uri uri) async {
    HapticFeedback.selectionClick();
    final isAction = _isActionLink(uri);

    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Opening ${_externalAppLabel(uri)}…'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: isAction ? LaunchMode.externalApplication : LaunchMode.inAppBrowserView,
      );
      if (!launched) {
        debugPrint("Could not launch external link: $uri");
      }
    } catch (e) {
      debugPrint("Could not launch external link: $uri ($e)");
    }
  }

  void _loadDrawerPath(String path) {
    HapticFeedback.selectionClick();
    _scaffoldKey.currentState?.closeDrawer();
    setState(() => _isNavigating = true);
    _controller?.loadRequest(Uri.parse(_buildUrl(path)));
  }

  void _syncBottomNavWithUrl(String url) {
    final path = Uri.parse(url).path;

    int newIndex = _currentIndex;

    if (path == "/" || path.isEmpty) {
      newIndex = 0;
    } else if (path.contains("/all-products")) {
      newIndex = 1;
    } else if (path.contains("/shop")) {
      newIndex = 2;
    } else if (path.contains("/shop/cart")) {
      newIndex = 3;
    } else if (path.contains("/web/login") || path.contains("/my")) {
      newIndex = 4;
    }

    // Rebuild only if something changed
    if (path != _currentPath || newIndex != _currentIndex) {
      setState(() {
        _currentPath = path;
        _currentIndex = newIndex;
      });
    }
  }

  void _injectCartCountObserver() {
    _controller?.runJavaScript(kCartCountScript);
  }

  void _injectHideElements() {
    _controller?.runJavaScript(kHideElementsScript);
  }

  void _injectScrollObserver() {
    _controller?.runJavaScript(kScrollObserverScript);
  }

  void _injectAuthCheck() {
    _controller?.runJavaScript(kAuthCheckScript);
  }

  void _injectCookieConsent() {
    _controller?.runJavaScript(kCookieConsentScript);
  }

  void _injectExternalLinkFix() {
    _controller?.runJavaScript(kExternalLinkFixScript);
  }

  // ================= PULL TO REFRESH =================

  void _handlePullStart(DragStartDetails details) {
    if (_isRefreshing) return;
  }

  void _handlePullUpdate(DragUpdateDetails details) {
    if (_isRefreshing) return;
    // Only engage the pull when the page is already scrolled to the top,
    // so this doesn't fight with normal in-page scrolling.
    if (_webScrollY > 5 && _pullDistance == 0) return;
    if (details.delta.dy <= 0 && _pullDistance == 0) return;

    setState(() {
      _pullDistance = (_pullDistance + details.delta.dy * 0.5).clamp(0, 100);
    });
  }

  void _handlePullEnd(DragEndDetails details) {
    if (_pullDistance >= _pullTriggerDistance) {
      HapticFeedback.mediumImpact();
      setState(() {
        _isRefreshing = true;
        _pullDistance = _pullTriggerDistance;
      });
      _controller?.reload();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _isRefreshing = false;
            _pullDistance = 0;
          });
        }
      });
    } else {
      setState(() => _pullDistance = 0);
    }
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final handled = await _tryGoBack();
        if (!handled) SystemNavigator.pop();
      },
      child: Scaffold(
        key: _scaffoldKey,

        appBar: AppBar(
          backgroundColor: Colors.white,
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.black),
              onPressed: () {
                HapticFeedback.selectionClick();
                Scaffold.of(ctx).openDrawer();
              },
            ),
          ),
          title: Row(
            children: [
              Image.asset("assets/icons/clickstocart_logo.png", height: 80),
            ],
          ),
          actions: [
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCountry,
                dropdownColor: Colors.white,
                icon: const Icon(Icons.public, color: Colors.black),
                style: const TextStyle(color: Colors.black),

                selectedItemBuilder: (context) {
                  return ["US", "CA"].map((value) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(value, style: const TextStyle(color: Colors.white)),
                        const SizedBox(width: 8),
                      ],
                    );
                  }).toList();
                },

                items: const [
                  DropdownMenuItem(value: "US", child: Text("US")),
                  DropdownMenuItem(value: "CA", child: Text("CA")),
                ],

                onChanged: (value) async {
                  if (value == null) return;

                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString("country", value);

                  setState(() {
                    _selectedCountry = value;
                    _currentIndex = 0;
                    _isNavigating = true;
                  });

                  _applyCountry(value);
                },
              ),
            ),

            const SizedBox(width: 12),
          ],

          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 0, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: _canGoBack ? Colors.black87 : Colors.black26,
                    ),
                    onPressed: _canGoBack ? _tryGoBack : null,
                  ),
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        textInputAction: TextInputAction.search,
                        onChanged: _onSearchChanged,
                        onSubmitted: _performSearch,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: "Search products...",
                          hintStyle: const TextStyle(color: Colors.black45, fontSize: 14),
                          prefixIcon: const Icon(Icons.search, color: Colors.black45, size: 20),
                          suffixIcon: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _searchController,
                            builder: (context, value, _) {
                              if (value.text.isEmpty) return const SizedBox.shrink();
                              return IconButton(
                                icon: const Icon(Icons.close, color: Colors.black45, size: 18),
                                onPressed: () => setState(() {
                                  _searchController.clear();
                                  _suggestions = [];
                                }),
                              );
                            },
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        drawer: Drawer(
          width: MediaQuery.of(context).size.width * 0.82,
          backgroundColor: const Color(0xFFF3F3F6),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: ListView(
            padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).padding.bottom),
            children: [
              _drawerHeader(),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: _quickActionsCard(),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _isLoggedIn
                    ? _groupCard([
                        _groupRow(
                          icon: Icons.account_circle,
                          label: _userName ?? "My Account",
                          iconColor: const Color(0xFFFC8000),
                          path: "/my/home",
                        ),
                      ])
                    : _groupCard([
                        _groupRow(
                          icon: Icons.login,
                          label: "Login / Sign up",
                          iconColor: const Color(0xFFFC8000),
                          textColor: const Color(0xFFFC8000),
                          path: "/web/login/",
                        ),
                      ]),
              ),

              _sectionLabel("SHOP"),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: _groupCard([
                  _groupRow(icon: Icons.home_outlined, label: "Home", path: "/"),
                  _groupRow(
                    icon: Icons.grid_view_outlined,
                    label: "All Products",
                    path: "/all-products/",
                  ),
                  _groupRow(
                    icon: Icons.celebration_outlined,
                    label: "Festival Collection",
                    path: "/festival-themed-collection/",
                  ),
                  _groupRow(
                    icon: Icons.checkroom_outlined,
                    label: "Indian Fashion",
                    path: "/authentic-indian-fashion/",
                  ),
                ]),
              ),

              if (_selectedCountry == "CA") ...[
                _sectionLabel("MARKETPLACE"),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: _groupCard([
                    _groupRow(
                      icon: Icons.storefront_outlined,
                      label: "Marketplace",
                      path: "/clickstocart-market",
                    ),
                    _groupRow(
                      icon: Icons.groups_outlined,
                      label: "Browse Sellers",
                      path: "/sellers",
                    ),
                    _groupRow(
                      icon: Icons.add_business_outlined,
                      label: "Become a Seller",
                      path: "/seller/signup",
                    ),
                    _groupRow(
                      icon: Icons.campaign_outlined,
                      label: "Classifieds",
                      path: "/classifieds",
                    ),
                  ]),
                ),
              ],

              _sectionLabel("MORE"),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: _groupCard([
                  _groupRow(icon: Icons.info_outline, label: "About Us", path: "/about-us/"),
                ]),
              ),

              _sectionLabel("FOLLOW US"),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: _socialLinksCard(),
              ),

              if (_isLoggedIn)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: _groupCard([
                    _groupRow(
                      icon: Icons.logout,
                      label: "Log out",
                      iconColor: Colors.redAccent,
                      textColor: Colors.redAccent,
                      onTap: _logout,
                    ),
                  ]),
                )
              else
                const SizedBox(height: 8),
            ],
          ),
        ),

        body: Stack(
          children: [
            if (_controller != null)
              Transform.translate(
                offset: Offset(0, _pullDistance),
                child: WebViewWidget(
                  controller: _controller!,
                  gestureRecognizers: {
                    Factory<VerticalDragGestureRecognizer>(
                      () => VerticalDragGestureRecognizer()
                        ..onStart = _handlePullStart
                        ..onUpdate = _handlePullUpdate
                        ..onEnd = _handlePullEnd,
                    ),
                  },
                ),
              ),

            // Pull-to-refresh indicator
            if (_pullDistance > 0)
              Positioned(
                top: _pullDistance / 2 - 18,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: _isRefreshing
                        ? const CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFC8000)),
                          )
                        : CircularProgressIndicator(
                            strokeWidth: 3,
                            value: (_pullDistance / _pullTriggerDistance).clamp(0, 1),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFC8000)),
                            backgroundColor: const Color(0xFFFC8000).withValues(alpha: 0.15),
                          ),
                  ),
                ),
              ),

            // 1. Top Progress Bar (Browser-style)
            if (_isNavigating && _loadingProgress < 1.0)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 3,
                child: LinearProgressIndicator(
                  value: _loadingProgress,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFC8000)),
                ),
              ),

            // 2. Premium Loading Overlay — cold start only, so tab switches
            // don't repeatedly flash a full-screen takeover like a browser reload.
            if (_isNavigating && _isFirstLoad)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 400),
                builder: (context, opacity, child) {
                  return Opacity(
                    opacity: opacity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white,
                            const Color(0xFFFFE1BC).withValues(alpha: 0.3),
                            Colors.white,
                          ],
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Hero(
                              tag: 'app_logo',
                              child: Image.asset(
                                "assets/icons/clickstocart_logo.png",
                                height: 120,
                              ),
                            ),
                            const SizedBox(height: 40),
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  const Color(0xFFFC8000).withValues(alpha: 0.8),
                                ),
                                backgroundColor: const Color(0xFFFC8000).withValues(alpha: 0.1),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _loadingProgress > 0
                                  ? "Loading... ${(_loadingProgress * 100).toInt()}%"
                                  : "Preparing your experience...",
                              style: const TextStyle(
                                color: Color(0xFFFC8000),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

            // 3. Offline / load-failure state
            if (_isOffline || _hasLoadError)
              OfflineView(
                onRetry: _retryLoad,
                icon: _isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
                title: _isOffline ? "You're offline" : "Something went wrong",
                message: _isOffline
                    ? "Check your internet connection and try again."
                    : "The page couldn't load right now.",
                detail: _isOffline ? null : _httpErrorDetail,
              ),

            // 4. Native search suggestions dropdown
            if (_searchFocused && _suggestions.isNotEmpty)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  elevation: 8,
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          dense: true,
                          leading: suggestion.isCategory
                              ? const Icon(Icons.category_outlined, color: Colors.black45)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: suggestion.imageUrl != null
                                      ? Image.network(
                                          suggestion.imageUrl!,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(
                                            Icons.image_not_supported_outlined,
                                            color: Colors.black26,
                                          ),
                                        )
                                      : const SizedBox(
                                          width: 40,
                                          height: 40,
                                          child: Icon(Icons.shopping_bag_outlined, color: Colors.black26),
                                        ),
                                ),
                          title: Text(
                            suggestion.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                          trailing: suggestion.price != null
                              ? Text(
                                  suggestion.price!,
                                  style: const TextStyle(
                                    color: Color(0xFFFC8000),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                )
                              : const Icon(Icons.chevron_right, size: 18, color: Colors.black26),
                          onTap: () => _selectSuggestion(suggestion),
                        );
                      },
                    ),
                  ),
                ),
              ),

            // 5. Floating support call button — always reachable, on every page
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: "supportCallFab",
                backgroundColor: const Color(0xFF2BB673),
                onPressed: _callSupport,
                child: const Icon(Icons.call, color: Colors.white),
              ),
            ),
          ],
        ),

        bottomNavigationBar: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.of(context).padding.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(Icons.home_outlined, 0, "Home"),
                _navItem(Icons.grid_view_outlined, 1, "Products"),
                _navItem(Icons.storefront, 2, "Shop"),
                _navItem(Icons.shopping_cart, 3, "Cart", showBadge: true),
                _accountNavItem(4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(
    IconData icon,
    int index,
    String label, {
    bool showBadge = false,
  }) {
    final active = _currentIndex == index;

    Widget iconWidget = Icon(icon, color: active ? Colors.orange : Colors.grey);

    if (showBadge && _cartCount != "0") {
      iconWidget = Badge(
        label: Text(
          _cartCount,
          style: const TextStyle(fontSize: 10, color: Colors.white),
        ),
        backgroundColor: Colors.red,
        child: iconWidget,
      );
    }

    return InkWell(
      onTap: () => _changeTab(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: active ? Colors.orange : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountNavItem(int index) {
    final active = _currentIndex == index;
    final color = active ? Colors.orange : Colors.grey;

    Widget iconWidget;
    if (_isLoggedIn) {
      final initial = (_userName?.isNotEmpty ?? false) ? _userName![0].toUpperCase() : "A";
      iconWidget = CircleAvatar(
        radius: 11,
        backgroundColor: color,
        child: Text(
          initial,
          style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      iconWidget = Icon(Icons.person, color: color);
    }

    return InkWell(
      onTap: () => _changeTab(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          Text(
            _isLoggedIn ? "Account" : "Login",
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }

  Widget _drawerHeader() {
    // The logo asset is already a full lockup (icon + wordmark + tagline),
    // so it's shown at its natural size on a clean background — no boxing,
    // no redundant text repeating what's already in the image.
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 20 + MediaQuery.of(context).padding.top, 20, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            "assets/icons/clickstocart_logo.png",
            height: 58,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          ),
          if (_isLoggedIn) ...[
            const SizedBox(height: 10),
            Text(
              "Hi, ${_userName ?? 'there'}!",
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFC8000),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  /// Small uppercase heading above a group card (e.g. "SHOP", "MORE") —
  /// the kind of section grouping native settings/menu screens use instead
  /// of a flat list of links.
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.black45,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  /// A rounded white card holding a set of [_groupRow]s with dividers
  /// between them — the grouped-list look most native app menus use,
  /// sitting on the drawer's light-grey background.
  Widget _groupCard(List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1) const Divider(height: 1, indent: 48, endIndent: 14),
          ],
        ],
      ),
    );
  }

  /// One row inside a [_groupCard]. Pass [path] for a normal nav destination
  /// (highlights itself when that's the current page) or [onTap] for a
  /// custom action like logout.
  Widget _groupRow({
    required IconData icon,
    required String label,
    String? path,
    VoidCallback? onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    const activeColor = Color(0xFFFC8000);
    final bool isSelected = path != null && (path == "/" ? _currentPath == "/" : _currentPath.startsWith(path));

    return InkWell(
      onTap: onTap ?? (path != null ? () => _loadDrawerPath(path) : null),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? (isSelected ? activeColor : Colors.black54)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor ?? (isSelected ? activeColor : Colors.black87),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.circle, size: 6, color: activeColor)
            else
              const Icon(Icons.chevron_right, size: 18, color: Colors.black26),
          ],
        ),
      ),
    );
  }

  /// Horizontal shortcut row (Orders / Wishlist / Cart / Support) right
  /// under the header — the "dashboard shortcuts" pattern most native
  /// shopping apps lead with, instead of only a list of page links.
  Widget _quickActionsCard() {
    final actions = <(IconData, String, Color, String)>[
      (Icons.receipt_long_outlined, "Orders", const Color(0xFF4C6FFF), "/my/orders"),
      (Icons.favorite_border, "Wishlist", const Color(0xFFFF5C8A), "/shop/wishlist"),
      (Icons.shopping_cart_outlined, "Cart", const Color(0xFFFC8000), "/shop/cart/"),
      (Icons.headset_mic_outlined, "Support", const Color(0xFF2BB673), "/contact-us/"),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final (icon, label, tint, path) in actions)
            _quickActionButton(icon: icon, label: label, tint: tint, path: path),
        ],
      ),
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required Color tint,
    required String path,
  }) {
    return InkWell(
      onTap: () => _loadDrawerPath(path),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  /// Facebook and Instagram links differ per storefront (separate country
  /// pages); X, YouTube, and Pinterest are shared across both. Pulled
  /// directly from the live site's own header links. TikTok is left out —
  /// the site's own TikTok link is still an unfilled placeholder ("#").
  Widget _socialLinksCard() {
    final facebookUrl = _selectedCountry == "CA"
        ? "https://www.facebook.com/share/19JGcFuBZ2/"
        : "https://www.facebook.com/share/1AkZfVqhqT/";
    final instagramUrl = _selectedCountry == "CA"
        ? "https://www.instagram.com/clicks_to_cart?igsh=ejcxanVvYjZnazR1"
        : "https://www.instagram.com/clicks_to_cart_us?igsh=cDM0bmo0ajl0aGt1";

    final links = <(FaIconData, String, Color, String)>[
      (FontAwesomeIcons.facebookF, "Facebook", const Color(0xFF1877F2), facebookUrl),
      (FontAwesomeIcons.instagram, "Instagram", const Color(0xFFE1306C), instagramUrl),
      (FontAwesomeIcons.xTwitter, "X", const Color(0xFF14171A), "https://x.com/clicks_to_cart"),
      (FontAwesomeIcons.youtube, "YouTube", const Color(0xFFFF0000), "https://www.youtube.com/@ClickstoCart"),
      (FontAwesomeIcons.pinterestP, "Pinterest", const Color(0xFFE60023), "https://pin.it/4NVEJkK"),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final (icon, label, tint, url) in links)
            _socialButton(icon: icon, label: label, tint: tint, url: url),
        ],
      ),
    );
  }

  Widget _socialButton({
    required FaIconData icon,
    required String label,
    required Color tint,
    required String url,
  }) {
    return InkWell(
      onTap: () => _launchExternally(Uri.parse(url)),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: FaIcon(icon, size: 16, color: tint),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
