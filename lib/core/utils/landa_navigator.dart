import 'package:flutter/material.dart';

/// The app's one `Navigator`, reachable from outside the widget tree.
///
/// Almost nothing should need this: a screen has its own `context`, and
/// reaching for a global key instead is how navigation stops being traceable.
/// It exists for exactly one class of caller: things that happen *to* the
/// user rather than because of them, and therefore have no context of their
/// own. A message arriving over the realtime socket is one; the popup it
/// raises has to find an `Overlay` and, if tapped, a route to push, and there
/// is no screen in the call stack to ask.
///
/// Registered on the `MaterialApp` in `main.dart`.
final GlobalKey<NavigatorState> landaNavigatorKey = GlobalKey<NavigatorState>();

/// The navigator's context, or null before the first frame.
///
/// Null is a real state and callers must handle it: the socket can deliver an
/// event during startup, before `MaterialApp` has built.
BuildContext? get landaNavigatorContext =>
    landaNavigatorKey.currentState?.context;

/// The overlay every route in the app is painted into.
///
/// Taken from the navigator directly rather than with `Overlay.of(context)`,
/// and that distinction is the whole reason this exists: a `Navigator` builds
/// its `Overlay` as a *descendant*, so an ancestor lookup from the
/// navigator's own context walks straight past it and finds nothing.
///
/// This is the right place for anything that has to appear over whatever is
/// on screen (a popup, a toast) because it outlives every route inside it.
OverlayState? get landaRootOverlay => landaNavigatorKey.currentState?.overlay;
