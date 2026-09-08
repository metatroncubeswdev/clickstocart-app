/// Injected JavaScript payloads used by [WebViewWithNav] to bridge the
/// Odoo-powered site with native chrome. Kept out of the widget file since
/// these are content, not UI logic.
library;

/// Hides the website's own header/footer/nav so it doesn't duplicate the
/// native app bar / bottom nav, and pulls page content up to fill the gap.
const String kHideElementsScript = """
  (function() {
    const css = `
      /* 1. Aggressively Hide Nav Elements (Odoo's actual header markup,
         plus a few generic fallbacks in case the theme changes) */
      header, footer, header#top, .main-header, #top_menu,
      .o_header_standard, .o_footer, #website_cookies_bar,
      .site-header, .site-footer, #header, #footer,
      .topbar, .navbar, .offcanvas,
      #pagetitle, .page-title, .header-title, .breadcrumb,
      .header-spacer, .header-gap, .fixed-header-space {
        display: none !important;
        height: 0 !important;
        min-height: 0 !important;
        padding: 0 !important;
        margin: 0 !important;
        visibility: hidden !important;
        opacity: 0 !important;
        pointer-events: none !important;
      }

      /* 2. Responsive Reset: Force content to the very top.
         #wrapwrap / #wrap are Odoo's real top-level wrappers — Odoo reserves
         top spacing on these for a fixed/sticky header, which hiding the
         header alone does not clear. */
      html, body, #wrapwrap, #wrap, #page, .site, #content, .site-content,
      .content-inner, #primary, .content-area, main, #main,
      .main-page-wrapper, .entry-content, .oe_structure:first-child {
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

    document.body.classList.add('app-view');
    document.body.classList.add('mobile-app-thankyou');

    function fixResponsiveGaps() {
      const selectors = ['header', 'footer', '#pagetitle', '.header-spacer'];
      selectors.forEach(s => {
        document.querySelectorAll(s).forEach(el => {
          if (el) el.style.setProperty('display', 'none', 'important');
        });
      });

      // Odoo (or its JS) may set an inline padding-top on the wrappers to
      // reserve space for the now-hidden fixed/sticky header — clear it
      // directly since it can outrank our stylesheet rule if it's inline.
      ['wrapwrap', 'wrap'].forEach(id => {
        const el = document.getElementById(id);
        if (el) {
          el.style.setProperty('padding-top', '0', 'important');
          el.style.setProperty('margin-top', '0', 'important');
        }
      });

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

    setTimeout(fixResponsiveGaps, 500);
    setTimeout(fixResponsiveGaps, 1500);
  })();
""";

/// Reports the cart item count to Flutter via `CartCountChannel`. Odoo
/// eCommerce (not WooCommerce) exposes the live count as JSON from
/// `/shop/cart` endpoints, so this hooks `fetch`/`XMLHttpRequest` rather than
/// scraping WooCommerce-specific DOM classes that don't exist on this site.
/// Falls back to reading the header cart badge for the initial page load.
const String kCartCountScript = """
  (function() {
    function notify(count) {
      try { CartCountChannel.postMessage(String(count)); } catch (e) {}
    }

    function extractCount(data) {
      if (!data || typeof data !== 'object') return null;
      if (typeof data.cart_quantity !== 'undefined') return data.cart_quantity;
      if (data.result && typeof data.result.cart_quantity !== 'undefined') return data.result.cart_quantity;
      return null;
    }

    if (!window.__c2cFetchPatched) {
      window.__c2cFetchPatched = true;
      const origFetch = window.fetch;
      window.fetch = function(...args) {
        return origFetch.apply(this, args).then(response => {
          try {
            const url = (args[0] && args[0].url) || args[0];
            if (typeof url === 'string' && url.indexOf('/shop/cart') !== -1) {
              response.clone().json().then(data => {
                const count = extractCount(data);
                if (count !== null) notify(count);
              }).catch(() => {});
            }
          } catch (e) {}
          return response;
        });
      };
    }

    if (!window.__c2cXhrPatched) {
      window.__c2cXhrPatched = true;
      const origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        this.__c2cUrl = url;
        return origOpen.call(this, method, url, ...rest);
      };
      const origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function(...args) {
        this.addEventListener('load', function() {
          try {
            if (typeof this.__c2cUrl === 'string' && this.__c2cUrl.indexOf('/shop/cart') !== -1) {
              const data = JSON.parse(this.responseText);
              const count = extractCount(data);
              if (count !== null) notify(count);
            }
          } catch (e) {}
        });
        return origSend.apply(this, args);
      };
    }

    function scanBadge() {
      const el = document.querySelector('.my_cart_quantity, .o_wsale_my_cart_quantity, [name="my_cart_quantity"]');
      if (el) {
        const m = (el.innerText || el.textContent || '').match(/\\d+/);
        if (m) notify(m[0]);
      }
    }

    scanBadge();
    setTimeout(scanBadge, 800);
  })();
""";

/// Reports the vertical scroll position to Flutter via `ScrollChannel`, so
/// native pull-to-refresh only engages when the page is scrolled to the top.
const String kScrollObserverScript = """
  (function() {
    if (window.__c2cScrollPatched) return;
    window.__c2cScrollPatched = true;

    function notify() {
      try { ScrollChannel.postMessage(String(window.scrollY || document.documentElement.scrollTop || 0)); } catch (e) {}
    }

    notify();
    window.addEventListener('scroll', notify, { passive: true });
  })();
""";

/// Asks Odoo's public session-info endpoint whether the current webview
/// session is authenticated, and reports the result to Flutter via
/// `AuthChannel`. Safe to call while anonymous — Odoo returns `uid: false`.
const String kAuthCheckScript = """
  (function() {
    fetch('/web/session/get_session_info', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', method: 'call', params: {} })
    }).then(r => r.json()).then(data => {
      const result = data && data.result;
      const uid = result && result.uid;
      const payload = uid
        ? { loggedIn: true, name: result.name || '', email: result.username || '' }
        : { loggedIn: false };
      try { AuthChannel.postMessage(JSON.stringify(payload)); } catch (e) {}
    }).catch(() => {});
  })();
""";

/// Writes Odoo's own cookies-bar consent cookie directly via document.cookie
/// so the accept/reject popup never has a reason to render. Odoo reads this
/// exact cookie name/shape via JSON.parse(), so the value MUST be raw JSON —
/// no encodeURIComponent. (A native WebViewCookieManager.setCookie() attempt
/// was tried first, but that API always percent-encodes the value before it
/// reaches the cookie jar, which Odoo's JSON.parse() can't read — on the CA
/// site that throws unhandled and surfaces as an HTTP 500. Always
/// (re)writing here, rather than only when the cookie is missing, ensures a
/// previously-broken value gets overwritten with a correct one too.)
const String kCookieConsentScript = """
  (function() {
    try {
      document.cookie = 'website_cookies_bar={"required":true,"optional":true}; path=/; max-age=31536000';
    } catch (e) {}
  })();
""";

/// webview_flutter_android enables WebView's multi-window support (to be
/// polite to target="_blank" links) but never implements actually showing
/// the resulting popup window — so any `window.open(...)` call, or a plain
/// `<a target="_blank">` click (WhatsApp/social buttons on the site
/// commonly use one of these), silently creates an invisible, orphaned
/// WebView and nothing visibly happens. This forces both patterns into a
/// normal same-window navigation instead, which the app's own
/// onNavigationRequest handler already intercepts and routes to the real
/// native app / an in-app browser tab.
const String kExternalLinkFixScript = """
  (function() {
    if (!window.__c2cWindowOpenPatched) {
      window.__c2cWindowOpenPatched = true;
      window.open = function(url) {
        if (url) { window.location.href = url; }
        return null;
      };
    }

    function stripBlankTargets() {
      document.querySelectorAll('a[target="_blank"]').forEach(function(a) {
        a.removeAttribute('target');
      });
    }

    stripBlankTargets();

    if (!window.__c2cBlankTargetObserver) {
      window.__c2cBlankTargetObserver = new MutationObserver(stripBlankTargets);
      window.__c2cBlankTargetObserver.observe(document.body, { childList: true, subtree: true });
    }
  })();
""";
