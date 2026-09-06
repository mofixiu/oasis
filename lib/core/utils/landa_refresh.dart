import 'dart:async';

import 'package:flutter/material.dart';

/// Watches route pushes and pops so screens can tell when they are back on
/// top.
///
/// Registered once on the [MaterialApp] in `main.dart`. Without it a screen
/// that pushes a detail page (approve an application, pay for a stay, accept
/// a job) comes back to whatever it was showing before, which is by then a
/// description of a world that has changed. Pull-to-refresh was the only way
/// to correct it, and users were doing it constantly.
final RouteObserver<ModalRoute<void>> landaRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// Keeps a screen's data fresh without the user dragging for it.
///
/// Four triggers, deliberately chosen rather than "refresh on every build":
///
/// * **On mount**: replaces the `addPostFrameCallback` every screen was
///   writing by hand, so the first fetch happens in exactly one place.
/// * **On return**: the screen becomes topmost again after a pushed route
///   pops. This is the one that mattered most: the pushed route is usually
///   where the state was changed.
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
    if (refreshOnMount) {
      // Post-frame rather than inline: loaders call `notifyListeners()`, and
      // notifying a provider during the first build throws.
      WidgetsBinding.instance.addPostFrameCallback((_) => refreshNow());
    }
    _restartPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-subscribed rather than subscribed once, because a screen can be
    // moved between routes and the observer keys on the route object.
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void> && route != _subscribedRoute) {
      if (_subscribedRoute != null) landaRouteObserver.unsubscribe(this);
      _subscribedRoute = route;
      landaRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_lifecycle != null) WidgetsBinding.instance.removeObserver(_lifecycle!);
    if (_subscribedRoute != null) landaRouteObserver.unsubscribe(this);
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
    if (refreshOnResume && mounted && _isTopmost) refreshNow();
    _restartPolling();
  }

  void _restartPolling() {
    _pollTimer?.cancel();
    final interval = autoRefreshInterval;
    if (interval == null) return;
    _pollTimer = Timer.periodic(interval, (_) {
      if (!mounted || !_isTopmost) return;
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
    if (refreshOnReturn) refreshNow();
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
const Duration kLandaPollInterval = Duration(seconds: 20);
