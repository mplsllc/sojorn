// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

class DesktopToast {
  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context, {
    required String message,
    IconData? icon,
    Color? color,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    // Dismiss any existing toast before showing a new one.
    _dismiss();

    final effectiveColor = color ?? AppTheme.brightNavy;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        icon: icon,
        color: effectiveColor,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismiss: () {
          _dismiss();
        },
      ),
    );

    _currentEntry = entry;
    Overlay.of(context).insert(entry);
  }

  static void _dismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
  }

  // ── Convenience methods ──────────────────────────────

  static void success(BuildContext context, String message) => show(
        context,
        message: message,
        icon: Icons.check_circle,
        color: Colors.green,
      );

  static void error(BuildContext context, String message) => show(
        context,
        message: message,
        icon: Icons.cancel,
        color: Colors.red,
      );

  static void info(BuildContext context, String message) => show(
        context,
        message: message,
        icon: Icons.info,
        color: AppTheme.brightNavy,
      );
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Color color;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.icon,
    required this.color,
    required this.duration,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _dismissTimer;
  double _progressFraction = 1.0;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    // Progress bar countdown — update at ~60fps.
    const tickInterval = Duration(milliseconds: 16);
    final totalMs = widget.duration.inMilliseconds;
    var elapsed = 0;

    _progressTimer = Timer.periodic(tickInterval, (timer) {
      elapsed += tickInterval.inMilliseconds;
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _progressFraction = (1.0 - elapsed / totalMs).clamp(0.0, 1.0);
      });
      if (elapsed >= totalMs) {
        timer.cancel();
      }
    });

    // Auto-dismiss after duration.
    _dismissTimer = Timer(widget.duration, _animateOut);
  }

  void _animateOut() {
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _progressTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 320,
              decoration: BoxDecoration(
                color: AppTheme.cardSurface,
                borderRadius: BorderRadius.circular(SojornRadii.card),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                    child: Row(
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 24, color: widget.color),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            widget.message,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.navyText,
                            ),
                          ),
                        ),
                        if (widget.actionLabel != null)
                          TextButton(
                            onPressed: () {
                              widget.onAction?.call();
                              _animateOut();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: widget.color,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              widget.actionLabel!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Progress bar
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(SojornRadii.card),
                      bottomRight: Radius.circular(SojornRadii.card),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 16),
                        height: 2,
                        width: 320 * _progressFraction,
                        color: widget.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
