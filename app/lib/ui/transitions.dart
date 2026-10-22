// HOW A SCREEN ARRIVES: A SMALL SLIDE IN FROM THE RIGHT WITH A FADE, THE SAME FOR EVERY SCREEN. THE FIRST SCREEN AND THE SIGN-IN FADE ONLY.
// With animations removed in the phone's settings every screen only fades, with no movement.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// -- CONSTANTS -- //

/// Coming in is a little slower than going out, so the new screen is not rushed and a back press is not slow.
const Duration pageIn = Duration(milliseconds: 280);
const Duration pageOut = Duration(milliseconds: 220);

/// How far from the side a screen starts, as a share of its own width. Small: a nudge, not a swipe.
const double _slideFrom = 0.06;

// -- FUNCTIONS -- //

/// The page for one route. [fadeOnly] is for the first screen and the sign-in, which are not "opened from" another.
Page<void> botlerPage(
  GoRouterState state,
  Widget child, {
  bool fadeOnly = false,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: pageIn,
    reverseTransitionDuration: pageOut,
    transitionsBuilder: (context, animation, _, page) {
      // In eases out, and on the way back it eases in, so going back is quick and sharp
      final shown = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      if (fadeOnly || MediaQuery.disableAnimationsOf(context)) {
        return FadeTransition(opacity: shown, child: page);
      }
      return FadeTransition(
        opacity: shown,
        child: SlideTransition(
          position: shown.drive(
            Tween<Offset>(begin: const Offset(_slideFrom, 0), end: Offset.zero),
          ),
          child: page,
        ),
      );
    },
  );
}
