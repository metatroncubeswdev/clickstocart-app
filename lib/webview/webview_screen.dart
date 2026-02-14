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
  bool _isNavigating = false;
  String _currentPath = "/";

  WebViewController? _controller;

  // ================= CONFIG =================
  static const String appParam = "1";

  String baseUrl = "https://clickstocartus.com/";
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
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isNavigating = true),
          onPageFinished: (url) {
            _syncBottomNavWithUrl(url);
            setState(() => _isNavigating = false);
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

            _menuItem("About ", "/about/"),

            // ---------- ALL PRODUCTS ----------
            _expandMenu("All Products", "/all-products/",[
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
            _expandMenu("Festival Themed Collection", "/festival-themed-collection/", [
              _menuItem(
                "Diyas Collection",
                "/festival-themed-collection/diwali-collections/",
              ),
              _menuItem(
                "Ganesh Chaturthi",
                "/festival-themed-collection/ganesh-chaturthi/",
              ),
              // FIXED: Navarathiri nested properly
              _expandMenu("Navarathiri Pooja", "/festival-themed-collection/navarathiri-pooja/", [
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
              ]),

              _menuItem(
                "Pongal Special",
                "/festival-themed-collection/pongal-special/",
              ),

              _menuItem(
                "Varalakshmi Pooja",
                "/festival-themed-collection/varalakshmi-pooja/",
              ),
            ]),

            // ---------- FASHION ----------
            _expandMenu("Authentic Indian Fashion", "/authentic-indian-fashion/",[
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
              _menuItem("Home Decor", "/authentic-indian-fashion/home-decor/"),
            ]),

            _menuItem("Blog", "/blog/"),
            _menuItem("Contact Us", "/contact-us/"),
          ],
        ),
      ),

      body: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),

          if (_isNavigating)
            const ColoredBox(
              color: Colors.white,
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFFC8000)),
              ),
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
                color: Colors.black.withOpacity(0.15),
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
              _navItem(Icons.shopping_cart, 3, "Cart"),
              _navItem(Icons.person, 4, "Account"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, int index, String label) {
    final active = _currentIndex == index;
    return InkWell(
      onTap: () => _changeTab(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: active ? Colors.orange : Colors.grey),
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
