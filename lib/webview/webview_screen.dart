import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WebViewWithNav extends StatefulWidget {
  const WebViewWithNav({super.key});

  @override
  State<WebViewWithNav> createState() => _WebViewWithNavState();
}

class _WebViewWithNavState extends State<WebViewWithNav> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _currentIndex = 0;
  bool _isNavigating = true; // Start with loader active
  double _loadingProgress = 0; // Add this
  String _currentPath = "/";
  String _cartCount = "0"; // Add this

  WebViewController? _controller;

  // ================= CONFIG =================
  static const String appParam = "1";

  String baseUrl = "https://clickstocartca.com/";
  String versionParam = "bf1c4c815a09";
  String _selectedCountry = "US";
  // =========================================


  List<String> _bottomNavUrls = [];

  @override
  void initState() {
    super.initState();
    _loadSavedCountry();
  }

  Future<void> _loadSavedCountry() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCountry = prefs.getString("country") ?? "US";

    _applyCountry(savedCountry, reload: false);
    _initWebView();
  }

  void _applyCountry(String country, {bool reload = true}) {
    if (country == "CA") {
      baseUrl = "https://clickstocartca.com/";
      versionParam = "05c7c5a71e52";
    } else {
      baseUrl = "https://clickstocartus.com/";
      versionParam = "bf1c4c815a09";
    }

    _selectedCountry = country;

    _bottomNavUrls = [
      "/",
      "/all-products/",
      "/shop/",
      "/cart/",
      "/my-account/",
    ].map(_buildUrl).toList();

    if (reload && _controller != null) {
      _controller!.loadRequest(Uri.parse(_bottomNavUrls.first));
    }
  }

  void _initWebView() {
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
      ..setUserAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isNavigating = true),
          onPageFinished: (url) {
            _syncBottomNavWithUrl(url);
            _injectCartCountObserver();
            _injectHideElements(); // Robustly hide web header/footer
            setState(() => _isNavigating = false);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
              Page resource error:
                code: ${error.errorCode}
                description: ${error.description}
                errorType: ${error.errorType}
                isForMainFrame: ${error.isForMainFrame}
            ''');
          },
          onHttpError: (HttpResponseError error) {
            debugPrint('HTTP error: ${error.response?.statusCode} for ${error.request?.uri}');
          },
          onProgress: (int progress) {
            setState(() {
              _loadingProgress = progress / 100.0;
            });
            
            // 🚀 ULTRA-FAST STRATEGY:
            // 1. Inject hiding CSS as soon as the page starts rendering (20%)
            // This ensures the header is GONE before the user even sees it.
            if (progress > 20 && progress < 100) {
              _injectHideElements();
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
          onNavigationRequest: (request) {
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
      ..loadRequest(Uri.parse(_bottomNavUrls.first));

    setState(() {}); // ensure rebuild after init
  }

  String _ensureAppAndVersion(String url) {
    final uri = Uri.parse(url);
    if (!uri.host.contains("clickstocart")) return url;

    final params = Map<String, String>.from(uri.queryParameters);
    params["app"] = appParam;
    params["v"] = versionParam;

    return uri.replace(queryParameters: params).toString();
  }

  String _buildUrl(String path) {
    return Uri.parse(
      "$baseUrl$path",
    ).replace(queryParameters: {"app": appParam, "v": versionParam}).toString();
  }

  void _changeTab(int index) {
    if (_currentIndex == index || _controller == null) return;

    setState(() {
      _currentIndex = index;
      _isNavigating = true;
    });

    _controller!.loadRequest(Uri.parse(_bottomNavUrls[index]));
  }

  void _loadDrawerPath(String path) {
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
    } else if (path.contains("/cart")) {
      newIndex = 3;
    } else if (path.contains("/my-account")) {
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
    if (_controller == null) return;

    debugPrint("Injecting refined Cart Count Observer (v9)");

    const String script = """
      (function() {
        console.log("Cart observer(v9) started on: " + window.location.href);
        
        function getCartCount() {
          let count = "0";

          // 1. If on Cart Page, count unique item rows (MOST RELIABLE for unique count)
          if (window.location.href.includes('/cart')) {
            // Count unique rows in the cart table
            const itemRows = document.querySelectorAll('.cart_item, .woocommerce-cart-form__cart-item, .cart-item, [class*="cart-item"]');
            if (itemRows.length > 0) {
              console.log("Found unique item rows: " + itemRows.length);
              return "" + itemRows.length;
            }
            
            // Fallback: count unique product names/links in the cart table
            const productLinks = document.querySelectorAll('.product-name a, .cart-item-title a');
            if (productLinks.length > 0) {
               // Use a Set to ensure we only count unique links if they appear multiple times
               const uniqueProducts = new Set();
               productLinks.forEach(link => uniqueProducts.add(link.href));
               console.log("Found unique product links: " + uniqueProducts.size);
               return "" + uniqueProducts.size;
            }
          }

          // 2. Try WooCommerce fragments (Check if it has a unique count)
          try {
            const fragments = JSON.parse(sessionStorage.getItem('wc_fragments'));
            if (fragments) {
              for (let key in fragments) {
                const html = fragments[key];
                const div = document.createElement('div');
                div.innerHTML = html;
                
                // Typical WooCommerce might only show total quantity in header, 
                // but we try to find a count element.
                const countEl = div.querySelector('.count, .cart-contents-count, .cart-count');
                if (countEl) {
                  const m = countEl.innerText.match(/\\d+/);
                  if (m) {
                    console.log("Found count via fragments: " + m[0]);
                    return m[0]; 
                  }
                }
              }
            }
          } catch (e) {}

          // 3. Fallback: Body Text Regex (usually total quantity, but better than nothing)
          const titleMatch = document.title.match(/\\(\\s*(\\d+)\\s*\\)/);
          if (titleMatch) return titleMatch[1];

          const bodyText = document.body.innerText;
          const cartPattern = bodyText.match(/Cart\\s*\\(\\s*(\\d+)\\s*\\)/i) || 
                             bodyText.match(/(\\d+)\\s*(item|items)\\s*in\\s*cart/i);
          if (cartPattern) return cartPattern[1];

          // 4. Common Selectors
          const selectors = ['.count', '.cart-contents-count', '.cart-count', '.header-cart-count', '.woodmart-cart-number'];
          for (let s of selectors) {
            const el = document.querySelector(s);
            if (el && el.innerText) {
              const m = el.innerText.match(/\\d+/);
              if (m) return m[0];
            }
          }

          return "0";
        }

        function notify() {
          try {
            const currentCount = getCartCount();
            console.log("Observer check, unique count: " + currentCount);
            CartCountChannel.postMessage(currentCount);
          } catch (e) {}
        }

        notify();
        
        let timeout;
        const debouncedNotify = () => {
          clearTimeout(timeout);
          timeout = setTimeout(notify, 1000);
        };

        const observer = new MutationObserver(debouncedNotify);
        observer.observe(document.body, { childList: true, subtree: true, characterData: true });

        document.addEventListener('input', debouncedNotify);
        document.addEventListener('change', debouncedNotify);
        
        if (window.jQuery) {
          window.jQuery(document.body).on('updated_wc_div updated_cart_totals added_to_cart removed_from_cart', function() {
            console.log("WooCommerce AJAX update detected");
            debouncedNotify();
          });
        }

        window.addEventListener('storage', notify);
      })();
    """;

    _controller!.runJavaScript(script);
  }

  void _injectHideElements() {
    if (_controller == null) return;

    debugPrint("Injecting Responsive Web Navigation & Gap Hider");

    const String script = """
      (function() {
        const css = `
          /* 1. Aggressively Hide Nav Elements */
          header, footer, .site-header, .site-footer, #header, #footer, 
          .ct-header, .topbar, #ct-header-wrap, .ct-header-wrap, .navbar, .offcanvas,
          #pagetitle, .page-title, .header-title, .ct-page-title, .ct-breadcrumb,
          .header-spacer, .header-gap, #ct-loadding, .fixed-header-space {
            display: none !important;
            height: 0 !important;
            min-height: 0 !important;
            padding: 0 !important;
            margin: 0 !important;
            visibility: hidden !important;
            opacity: 0 !important;
            pointer-events: none !important;
          }
          
          /* 2. Responsive Reset: Force content to the very top */
          html, body, #page, .site, #content, .site-content, .content-inner, 
          #primary, .content-area, main, #main, .main-page-wrapper, .entry-content,
          .elementor-section-wrap, .elementor {
            padding-top: 0 !important;
            margin-top: 0 !important;
            top: 0 !important;
            position: relative !important;
          }

          /* 3. Handle specific theme 'sticky' placeholders */
          .fixed-height, .is-sticky, .sticky-header-active {
            height: auto !important;
            padding-top: 0 !important;
          }

          /* 4. Ensure no hidden overflows cause gaps */
          .site-header-active {
            padding-top: 0 !important;
          }
        `;
        
        const head = document.head || document.getElementsByTagName('head')[0];
        const style = document.createElement('style');
        style.type = 'text/css';
        style.appendChild(document.createTextNode(css));
        head.appendChild(style);
        
        // Add helper classes to body to trigger existing site-hiding CSS
        document.body.classList.add('app-view');
        document.body.classList.add('mobile-app-thankyou');
        
        // Secondary Dynamic Fix for responsive gaps
        function fixResponsiveGaps() {
          const selectors = ['header', 'footer', '#ct-header-wrap', '#pagetitle', '.header-spacer'];
          selectors.forEach(s => {
            document.querySelectorAll(s).forEach(el => {
              if (el) el.style.setProperty('display', 'none', 'important');
            });
          });

          // Look for any div with height/padding at the very top of the screen
          const topElements = document.querySelectorAll('div, section, header');
          topElements.forEach(el => {
            const rect = el.getBoundingClientRect();
            if (rect.top === 0 && rect.height > 0 && rect.height < 200) {
              const style = window.getComputedStyle(el);
              if (style.position === 'fixed' || style.position === 'absolute') {
                 el.style.setProperty('display', 'none', 'important');
              }
            }
          });
        }
        
        fixResponsiveGaps();
        const observer = new MutationObserver(fixResponsiveGaps);
        observer.observe(document.body, { childList: true, subtree: true });
        
        // Final pass after a delay to catch late-renders
        setTimeout(fixResponsiveGaps, 500);
        setTimeout(fixResponsiveGaps, 1500);
      })();
    """;

    _controller!.runJavaScript(script);
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,

      appBar: AppBar(
        backgroundColor: const Color(0xFFFC8000),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Color(0xFFFFE1BC)),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            Image.asset("assets/icons/cart_transp.png", height: 32),
            const SizedBox(width: 10),
            const Text("Clicks To Cart", style: TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedCountry,
              dropdownColor: Colors.white,
              icon: const Icon(Icons.public, color: Colors.white),
              style: const TextStyle(color: Colors.black),

              // 👇 This controls how the selected value looks
              selectedItemBuilder: (context) {
                return ["US", "CA"].map((value) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(value, style: const TextStyle(color: Colors.white)),
                      const SizedBox(width: 8), // ✅ spacing here
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
      ),

      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              child: Image.asset(
                "assets/icons/clickstocart_logo.png",
                fit: BoxFit.contain,
              ),
            ),
            _menuItem("Home", "/"),

            _menuItem("About ", "/about-us/"),

            // ---------- ALL PRODUCTS ----------
            _expandMenu("All Products", "/all-products/", [
              _menuItem(
                "Fresh Flower Collection",
                "/all-products/fresh-flower-collection/",
              ),
              _menuItem(
                "Other Pooja Products",
                "/all-products/other-pooja-products/",
              ),
              _menuItem(
                "Traditional South Indian Sweets",
                "/all-products/traditional-south-indian-sweets/",
              ),
              _menuItem(
                "Grocery Products Collection",
                "/all-products/grocery-products-collection/",
              ),
              _menuItem("Fresh Produce", "/all-products/fresh-produce/"),
              _menuItem("Fresh Fruits", "/all-products/fresh-fruit/"),
            ]),

            // ---------- FESTIVAL ----------
            _expandMenu(
              "Festival Themed Collection",
              "/festival-themed-collection/",
              [
                _menuItem(
                  "Diyas Collection",
                  "/festival-themed-collection/diwali-collections/",
                ),
                _menuItem(
                  "Ganesh Chaturthi",
                  "/festival-themed-collection/ganesh-chaturthi/",
                ),
                // FIXED: Navarathiri nested properly
                _expandMenu(
                  "Navarathiri Pooja",
                  "/festival-themed-collection/navarathiri-pooja/",
                  [
                    _menuItem(
                      "Pre-Order Golu Collections",
                      "/festival-themed-collection/navarathiri-pooja/pre-order-golu-collections/",
                    ),
                    _menuItem(
                      "In-Stock Golu Doll Collection",
                      "/festival-themed-collection/navarathiri-pooja/in-stock-golu-doll-collection/",
                    ),
                    _menuItem(
                      "Return Gift Collection",
                      "/festival-themed-collection/navarathiri-pooja/return-gift-collection/",
                    ),
                  ],
                ),

                _menuItem(
                  "Pongal Special",
                  "/festival-themed-collection/pongal-special/",
                ),

                _menuItem(
                  "Varalakshmi Pooja",
                  "/festival-themed-collection/varalakshmi-pooja/",
                ),
              ],
            ),

            // ---------- FASHION ----------
            _expandMenu(
              "Authentic Indian Fashion",
              "/authentic-indian-fashion/",
              [
                _menuItem(
                  "Silk4U Collection",
                  "/authentic-indian-fashion/silk4u-collection/",
                ),
                _menuItem(
                  "Devii Sutraa",
                  "/authentic-indian-fashion/devii-sutraa/",
                ),
                _menuItem(
                  "Fancy Jewelry Collection",
                  "/authentic-indian-fashion/fancy-jewelry-collection/",
                ),
                _menuItem(
                  "Handcrafted Jewelry Collection",
                  "/authentic-indian-fashion/handcrafted-jewelry-collection/",
                ),
                _menuItem(
                  "Home Decor",
                  "/authentic-indian-fashion/home-decor/",
                ),
              ],
            ),

            _menuItem("Blog", "/blog/"),
            _menuItem("Contact Us", "/contact-us/"),
          ],
        ),
      ),

      body: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),

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

          // 2. Premium Loading Overlay
          if (_isNavigating)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              builder: (context, opacity, child) {
                return Opacity(
                  opacity: opacity,
                  child: Container(
                    // Professional Gradient Background
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
                          // Large Animated Logo
                          Hero(
                            tag: 'app_logo',
                            child: Image.asset(
                              "assets/icons/clickstocart_logo.png",
                              height: 120, // Slightly larger for initial load
                            ),
                          ),
                          const SizedBox(height: 40),
                          // Custom Styled Spinner
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
        ],
      ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
              _navItem(Icons.person, 4, "Account"),
            ],
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

  Widget _menuItem(String title, String path) {
    final bool isSelected = path == "/"
        ? _currentPath == "/"
        : _currentPath.startsWith(path);

    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? const Color(0xFFFC8000) : Colors.black,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: () => _loadDrawerPath(path),
    );
  }

  bool _isInSection(String sectionPath) {
    return _currentPath.startsWith(sectionPath);
  }

  Widget _expandMenu(String title, String sectionPath, List<Widget> children) {
    final bool expanded = _isInSection(sectionPath);

    return ExpansionTile(
      initiallyExpanded: expanded,
      title: Text(
        title,
        style: TextStyle(
          color: expanded ? const Color(0xFFFC8000) : Colors.black,
          fontWeight: expanded ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      children: children,
    );
  }
}
