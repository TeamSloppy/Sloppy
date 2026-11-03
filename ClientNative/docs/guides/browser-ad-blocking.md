# Browser ad blocking

Sloppy's Browse workspace blocks ads using WebKit content rule lists on macOS,
iPhone and iPad. Blocking is enabled by default. The app includes EasyList in
WebKit's JSON format, so the first page is protected without a network download.
The list contains network blocking rules, cosmetic hiding rules and exceptions;
it does not provide every capability of a full browser-extension filter engine.

On macOS, click the shield beside the address or choose **Ad Blocking** from the
browser menu. On iPhone and iPad, open the browser menu and choose **Ad Blocking**.
The screen provides a global switch, a switch for the current site, the list's
rule count and last successful update check, manual updating, automatic updating,
and a list of site exceptions that can be removed.

Site exceptions include the selected host and its subdomains. They apply to the
top-level page and its resources, including resources inside cross-origin frames.
Other hosts remain protected. Toggling protection reloads the page whose settings
you opened; reload other open pages to fully apply changes. Global preferences
and site exceptions persist locally across restarts.

When automatic updating is enabled, navigation checks whether the last successful
check is at least 24 hours old. Downloads run separately from page loading; failed
automatic checks retry no more than hourly during later navigation. Conditional
requests use the server's ETag and Last-Modified headers when available. Manual
checks bypass the interval. A successful update applies to all live Browse pages
for subsequent requests; pages are not automatically reloaded or edited.

Update source:
<https://easylist-downloads.adblockplus.org/easylist_content_blocker.json>

Responses must be HTTPS, HTTP 200 with a nonempty JSON rule array, or HTTP 304
for a conditional check. Downloads are bounded to 20 MiB and 150,000 rules.
Sloppy accepts only declarative block, block-cookies, CSS hiding, exception and
HTTPS upgrade actions. WebKit must compile a download before it is saved. Invalid
responses, compiler errors and offline failures retain the last working list.
An invalid cache falls back to the bundled list. Errors remain visible on the
Ad Blocking screen. Update requests contain no visited URLs or browsing history.

Rules are installed through each WKWebView's user content controller before the
first HTTP(S) main-frame navigation is allowed. Updating or disabling Sloppy's
rules removes only its own rule list; extension lists and user scripts are kept.
Discarded pages detach from the shared service; recreated pages attach again.

Filter data attribution: The EasyList authors (<https://easylist.to/>).
The bundled data is distributed under CC BY-SA 3.0; the resource notice includes
its source and modification details. Updating does not execute downloaded scripts.
