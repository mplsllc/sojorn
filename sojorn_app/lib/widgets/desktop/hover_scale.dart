// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';

/// Wraps any child with a subtle scale + elevation lift on mouse hover.
/// Desktop-only — on mobile it renders the child unmodified.
///
/// Usage:
///   HoverScale(child: MyCard(...))
///   HoverScale(scale: 1.01, child: SidebarWidget(...))
class HoverScale extends StatefulWidget {
  final Widget child;
  final double scale;
  final double elevationDelta;
  final Duration duration;
  final BorderRadius? borderRadius;

  const HoverScale({
    super.key,
    required this.child,
    this.scale = 1.02,
    this.elevationDelta = 2.0,
    this.duration = const Duration(milliseconds: 150),
    this.borderRadius,
  });

  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (!isDesktop) return widget.child;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? widget.scale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: widget.duration,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: _hovering
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
