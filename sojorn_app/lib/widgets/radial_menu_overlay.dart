// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class RadialMenuOverlay extends StatefulWidget {
  final bool isVisible;
  final VoidCallback onDismiss;
  final VoidCallback onPostTap;
  final VoidCallback onQuipTap;
  final VoidCallback onBeaconTap;

  const RadialMenuOverlay({
    super.key,
    required this.isVisible,
    required this.onDismiss,
    required this.onPostTap,
    required this.onQuipTap,
    required this.onBeaconTap,
  });

  @override
  State<RadialMenuOverlay> createState() => _RadialMenuOverlayState();
}

class _RadialMenuOverlayState extends State<RadialMenuOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Rebuild when animation dismisses so the SizedBox.shrink check fires
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() {});
      }
    });

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(RadialMenuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible && _controller.isDismissed) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: !widget.isVisible,
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            children: [
              // Backdrop with blur
              Positioned.fill(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      color: SojornColors.overlayDark,
                    ),
                  ),
                ),
              ),
              // Radial menu items
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildRadialMenu(),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  Widget _buildRadialMenu() {
    // Position items in an arc above the bottom center
    final screenWidth = MediaQuery.of(context).size.width;
    final centerX = screenWidth / 2;
    
    // Arc parameters - position from bottom up
    const radius = 126.0;
    const startAngle = math.pi * 0.75; // 135 degrees (left)
    const endAngle = math.pi * 0.25;   // 45 degrees (right)
    
    final items = [
      _MenuItem(
        icon: Icons.edit_outlined,
        label: 'Post',
        onTap: () {
          widget.onDismiss();
          widget.onPostTap();
        },
        angle: startAngle,
      ),
      _MenuItem(
        icon: Icons.location_on_outlined,
        label: 'Beacon',
        onTap: () {
          widget.onDismiss();
          widget.onBeaconTap();
        },
        angle: (startAngle + endAngle) / 2, // Middle (top)
      ),
      _MenuItem(
        icon: Icons.videocam_outlined,
        label: 'Quip',
        onTap: () {
          widget.onDismiss();
          widget.onQuipTap();
        },
        angle: endAngle,
      ),
    ];

    return SizedBox(
      height: 220,
      child: Stack(
        clipBehavior: Clip.none,
        children: items.map((item) {
          // Calculate position in arc
          final dx = centerX + radius * math.cos(item.angle);
          // Position from top of container (lowered for easier reach)
          final dy = 220 - 20 - (radius * math.sin(item.angle));
          
          return Positioned(
            left: dx - 35, // Center the 70px button
            top: dy - 35,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: _MenuButton(
                icon: item.icon,
                label: item.label,
                onTap: item.onTap,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double angle;

  _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.angle,
  });
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: SojornColors.basicWhite,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: SojornColors.overlayScrim,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: AppTheme.navyBlue,
              size: 36,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: SojornColors.basicWhite,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: SojornColors.overlayScrim,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.navyBlue,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
