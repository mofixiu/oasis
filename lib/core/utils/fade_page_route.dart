import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The one way a screen is pushed in this app.
///
/// **One movement.** Every push moves the same way. The app used to mix
/// `MaterialPageRoute` (slide up on Android, slide across on iOS) with a plain
/// fade at roughly two call sites in three, so the same tap moved the screen
/// differently depending on which file it happened to be written in.
///
/// **Swipe back.** On iOS, dragging from the left edge to go back is not a
/// feature, it is how the phone works: every native app does it, and one that
/// does not feels broken in a way people rarely articulate.
///
/// Those two turn out to be the same requirement, which is why this is a
/// `CupertinoPageRoute` and why it does *not* override the transition. The
/// edge-drag gesture is installed by `CupertinoRouteTransitionMixin` inside
/// the transition it builds: replace the animation with a fade of your own and
/// the detector goes with it, and the gesture silently stops working, which
/// is exactly what happened the first time this was written. The horizontal
/// slide is also the movement the gesture is the inverse of; a screen that
/// fades in cannot be meaningfully dragged back out.
///
/// So the app's one movement is the iOS one, on every platform. It is the
/// motion the primary audience already has in their hands, and it comes with
/// the parallax on the outgoing screen, the shadow down its leading edge, the
/// rubber-banding, and the half-swipe cancel: none of which is worth
/// rebuilding to arrive somewhere slightly different.
class OasisPageRoute<T> extends CupertinoPageRoute<T> {
  OasisPageRoute({required Widget page, super.settings})
    : super(builder: (_) => page);
}

/// The previous name. Kept so nothing has to change at a call site to get the
/// gesture.
typedef FadePageRoute<T> = OasisPageRoute<T>;

/// The same movement for routes the framework builds on its own: generated
/// routes, dialogs, anything pushed without [OasisPageRoute].
///
/// Registered for every platform in `AppTheme`, so a `MaterialPageRoute` that
/// slips into the codebase still moves like the rest of the app and still
/// answers the back-swipe.
typedef OasisPageTransitionsBuilder = CupertinoPageTransitionsBuilder;

/// The previous name, for the theme's transition table.
typedef FadePageTransitionsBuilder = OasisPageTransitionsBuilder;
