import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Watches route pushes and pops so screens can tell when they are back on
/// top.
///
/// Registered once on the [MaterialApp] in `main.dart`. Without it a screen
/// that pushes a detail page (approve an application, pay for a stay, accept
/// a job) comes back to whatever it was showing before, which is by then a
/// description of a world that has changed. Pull-to-refresh was the only way
/// to correct it, and users were doing it constantly.
final RouteObserver<ModalRoute<void>> oasisRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// Tells the subtree which tab it is sitting in, and which tab is on screen.
///
/// `MainScaffold` renders its tabs in an `IndexedStack`, which keeps every
/// visited tab alive so scroll position and loaded data survive a switch.
/// The side effect is that switching tabs is invisible to everything else:
/// no route is pushed, no route pops, nothing is mounted or disposed. So a
/// landlord going Dashboard → Applications → Dashboard came back to the
/// dashboard exactly as they left it, however long ago that was, and the
/// only way to correct it was to pull down. That is most of what testers
/// meant by "I have to refresh everything to see".
///
/// [AutoRefreshMixin] listens for this and treats becoming the visible tab
/// the same way it treats a pushed route popping: the moment the screen's
/// data is most likely stale.
///
/// It also defers the *first* load of a tab nobody has looked at yet. An
/// `IndexedStack` builds all of its children at once, so without this every
/// tab fires its opening fetch the instant the app opens — four screens'
/// worth of requests on a phone that is showing one of them.
class OasisTabVisibility extends InheritedWidget {
  /// Which tab is currently on screen.
  final ValueListenable<int> activeIndex;

  /// Which tab this subtree is.
  final int index;

  const OasisTabVisibility({
    super.key,
    required this.activeIndex,
    required this.index,
    required super.child,
  });

  static OasisTabVisibility? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OasisTabVisibility>();

  bool get isVisible => activeIndex.value == index;

  @override
  bool updateShouldNotify(OasisTabVisibility oldWidget) =>
      oldWidget.activeIndex != activeIndex || oldWidget.index != index;
}

/// Keeps a screen's data fresh without the user dragging for it.
///
/// Five triggers, deliberately chosen rather than "refresh on every build":
///
/// * **On mount**: replaces the `addPostFrameCallback` every screen was
///   writing by hand, so the first fetch happens in exactly one place. Inside
///   a tab it is deferred until that tab is first looked at.
/// * **On return**: the screen becomes topmost again after a pushed route
///   pops. This is the one that mattered most: the pushed route is usually
///   where the state was changed.
/// * **On becoming the visible tab**: the same idea for the bottom bar, which
///   pushes and pops nothing. See [OasisTabVisibility].
/// * **On resume**: the app comes back from the background. A booking's
///   24-hour payment window, an artisan's queue and an escrow release all
///   move on while the phone is in a pocket.
/// * **On an interval**: opt-in, for screens where someone else acts and
///   this user is waiting: a guest watching for approval, an artisan watching
///   for work. Off by default, because polling a screen nobody is waiting on
///   is just battery.
///
/// Refreshes are *silent*: they call the same loader pull-to-refresh calls,
/// and screens keep rendering the data they already have while it runs. That
/// is why the loading branch on every list is written as "loading **and**
/// empty": a background refresh must never blank content that is on screen.
///
/// Overlapping refreshes are dropped rather than queued. A slow request plus
/// a 20-second timer would otherwise stack calls faster than they complete.
mixin AutoRefreshMixin<T extends StatefulWidget> on State<T>
    implements RouteAware {
  Timer? _pollTimer;
  bool _isRefreshing = false;
  ModalRoute<void>? _subscribedRoute;
  _LifecycleBridge? _lifecycle;

  /// True while this screen is the topmost route. Polling pauses otherwise:
  /// a screen buried under three pushed pages is not being read.
  bool _isTopmost = true;

  /// True while the tab this screen sits in is the one on screen. Always true
  /// for a screen that is not inside a tab at all.
  bool _isTabVisible = true;

  /// The tab context, when there is one, and the listener attached to it.
  OasisTabVisibility? _tab;
  VoidCallback? _tabListener;

  /// Whether the opening fetch has happened. Tracked rather than fired blindly
  /// in `initState`, because a tab that is built but not shown should not
  /// fetch until somebody looks at it.
  bool _didInitialRefresh = false;

  /// Whether this screen may fetch right now: on screen in both senses.
  bool get _isActive => _isTopmost && _isTabVisible;

  /// Fetches this screen's data. The same method pull-to-refresh uses, so
  /// there is only ever one definition of "reload this page".
  Future<void> onAutoRefresh();

  /// How often to re-fetch while the screen is visible and topmost. Null (the
  /// default) means no polling.
  Duration? get autoRefreshInterval => null;

  /// Whether to fetch as soon as the screen mounts. Off for screens handed
  /// their data by the caller.
  bool get refreshOnMount => true;

  /// Whether returning from a pushed route re-fetches.
  bool get refreshOnReturn => true;

  /// Whether the app coming back to the foreground re-fetches.
  bool get refreshOnResume => true;

  @override
  void initState() {
    super.initState();
    _lifecycle = _LifecycleBridge(onResume: _handleResume);
    WidgetsBinding.instance.addObserver(_lifecycle!);
    // Post-frame rather than inline: loaders call `notifyListeners()`, and
    // notifying a provider during the first build throws. By then
    // `didChangeDependencies` has run, so the tab check below is answerable.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialRefresh());
    _restartPolling();
  }

  /// The opening fetch, once this screen is actually being looked at.
  void _initialRefresh() {
    if (!mounted || _didInitialRefresh || !refreshOnMount) return;
    // Built inside a tab nobody has opened yet: wait. The fetch runs the
    // first time that tab is shown, which is the first moment its data is
    // worth anything.
    if (!_isTabVisible) return;
    _didInitialRefresh = true;
    refreshNow();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-subscribed rather than subscribed once, because a screen can be
    // moved between routes and the observer keys on the route object.
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void> && route != _subscribedRoute) {
      if (_subscribedRoute != null) oasisRouteObserver.unsubscribe(this);
      _subscribedRoute = route;
      oasisRouteObserver.subscribe(this, route);
    }
    _attachTab(OasisTabVisibility.of(context));
  }

  void _attachTab(OasisTabVisibility? tab) {
    if (tab == null) {
      _detachTab();
      _isTabVisible = true;
      return;
    }
    if (_tab?.activeIndex == tab.activeIndex && _tab?.index == tab.index) {
      return;
    }
    _detachTab();
    _tab = tab;
    _tabListener = _handleTabChanged;
    tab.activeIndex.addListener(_tabListener!);
    _isTabVisible = tab.isVisible;
  }

  void _detachTab() {
    if (_tab != null && _tabListener != null) {
      _tab!.activeIndex.removeListener(_tabListener!);
    }
    _tab = null;
    _tabListener = null;
  }

  /// The bottom bar moved. Becoming visible is treated exactly like a pushed
  /// route popping, because to the user it is the same event: they have come
  /// back to a page that has been sitting still while things changed.
  void _handleTabChanged() {
    final visible = _tab?.isVisible ?? true;
    if (visible == _isTabVisible) return;
    _isTabVisible = visible;
    if (!visible) {
      _pollTimer?.cancel();
      return;
    }
    _restartPolling();
    if (!_didInitialRefresh) {
      _initialRefresh();
    } else if (refreshOnReturn) {
      refreshNow();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _detachTab();
    if (_lifecycle != null) WidgetsBinding.instance.removeObserver(_lifecycle!);
    if (_subscribedRoute != null) oasisRouteObserver.unsubscribe(this);
    super.dispose();
  }

  /// Re-fetches now, unless a refresh is already in flight.
  ///
  /// Public so a screen can call it after it changes something itself: an
  /// approval, a payment, and get the backend's version of the result rather
  /// than patching the list locally and hoping the two agree.
  Future<void> refreshNow() async {
    if (_isRefreshing || !mounted) return;
    _isRefreshing = true;
    try {
      await onAutoRefresh();
    } finally {
      _isRefreshing = false;
    }
  }

  void _handleResume() {
    if (refreshOnResume && mounted && _isActive) {
      // A tab that was never opened has still not loaded: resuming is as good
      // a moment as any to notice it is now the visible one.
      _didInitialRefresh ? refreshNow() : _initialRefresh();
    }
    _restartPolling();
  }

  void _restartPolling() {
    _pollTimer?.cancel();
    final interval = autoRefreshInterval;
    if (interval == null) return;
    _pollTimer = Timer.periodic(interval, (_) {
      if (!mounted || !_isActive) return;
      refreshNow();
    });
  }

  // ------------------------------------------------------------- RouteAware

  /// Something was pushed on top of this screen. Stop polling behind it.
  @override
  void didPushNext() {
    _isTopmost = false;
    _pollTimer?.cancel();
  }

  /// The pushed route popped and this screen is topmost again: the moment
  /// its data is most likely to be out of date.
  @override
  void didPopNext() {
    _isTopmost = true;
    _restartPolling();
    if (refreshOnReturn && _isTabVisible) refreshNow();
  }

  @override
  void didPush() => _isTopmost = true;

  @override
  void didPop() {
    _isTopmost = false;
    _pollTimer?.cancel();
  }
}

/// Bridges app lifecycle events into the mixin.
///
/// A separate object rather than making the [State] a [WidgetsBindingObserver]
/// itself: several screens already are one for their own reasons (returning
/// from a payment checkout browser, most of all), and two `didChangeAppLifecycleState`
/// overrides on one class cannot coexist.
class _LifecycleBridge with WidgetsBindingObserver {
  final VoidCallback onResume;

  _LifecycleBridge({required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// How often screens poll where someone else's action is what this user is
/// waiting for.
///
/// One constant rather than a number per screen, so the app has a single
/// answer to "how stale can this get": twenty seconds, which is under the
/// time it takes to read a page and long enough not to be a drain.
const Duration kOasisPollInterval = Duration(seconds: 20);
