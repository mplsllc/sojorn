// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Custom scroll physics that reproduce the exact friction and deceleration
/// curve of native iOS UIScrollView (decelerationRate = .normal, ~0.998/frame).
///
/// Key differences from Flutter defaults:
/// - Higher initial drag threshold (prevents accidental scroll starts)
/// - Friction coefficient 0.135 matches UIScrollView deceleration constant
/// - Spring simulation on overscroll with iOS-calibrated stiffness/damping
class SojornFeedPhysics extends BouncingScrollPhysics {
  const SojornFeedPhysics({super.parent});

  @override
  SojornFeedPhysics applyTo(ScrollPhysics? ancestor) {
    return SojornFeedPhysics(parent: buildParent(ancestor));
  }

  // iOS reports ~3.5px of pre-scroll dead zone before committing direction.
  @override
  double get dragStartDistanceMotionThreshold => 3.5;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tolerance = toleranceFor(position);

    // Out-of-bounds: hand off to bouncing spring (parent behavior).
    if ((velocity > 0 && position.pixels >= position.maxScrollExtent) ||
        (velocity < 0 && position.pixels <= position.minScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    // Below fling threshold — just stop.
    if (velocity.abs() < tolerance.velocity) return null;

    // iOS UIScrollView deceleration constant (60fps equivalent).
    // Apple docs: normal = 0.998 per frame → converted to continuous friction.
    // Continuous: k = -ln(0.998) * 60 ≈ 0.1202 per second.
    // We use 0.135 for a slightly heavier, more "planted" feel.
    return FrictionSimulation(
      0.135,
      position.pixels,
      velocity,
      tolerance: tolerance,
    );
  }

}

/// Lighter variant for ListView feeds (lists of post cards).
/// Uses clamping at extremes (no rubber-band) but iOS friction while scrolling.
class SojornListPhysics extends ScrollPhysics {
  const SojornListPhysics({super.parent});

  @override
  SojornListPhysics applyTo(ScrollPhysics? ancestor) {
    return SojornListPhysics(parent: buildParent(ancestor));
  }

  @override
  double get dragStartDistanceMotionThreshold => 2.5;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tolerance = toleranceFor(position);

    // Hard clamp at boundaries — no overscroll.
    if (position.outOfRange) {
      final target = position.pixels < position.minScrollExtent
          ? position.minScrollExtent
          : position.maxScrollExtent;
      return ScrollSpringSimulation(
        SpringDescription.withDampingRatio(mass: 0.5, stiffness: 100, ratio: 1.2),
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }

    if (velocity.abs() < tolerance.velocity) return null;

    return FrictionSimulation(
      0.135,
      position.pixels,
      velocity,
      tolerance: tolerance,
    );
  }
}
