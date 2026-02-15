import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/tokens.dart';

/// Radial speed-dial FAB for quickly reporting different beacon types.
/// Expands into 4 options: Hazard (map), Activity (map), Message (board), Resource (board).
class ReportSpeedDial extends StatefulWidget {
  final VoidCallback? onReportHazard;
  final VoidCallback? onReportActivity;
  final VoidCallback? onPostMessage;
  final VoidCallback? onShareResource;

  const ReportSpeedDial({
    super.key,
    this.onReportHazard,
    this.onReportActivity,
    this.onPostMessage,
    this.onShareResource,
  });

  @override
  State<ReportSpeedDial> createState() => _ReportSpeedDialState();
}

class _ReportSpeedDialState extends State<ReportSpeedDial>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _close() {
    if (_isOpen) _toggle();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 260,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          // ── Backdrop (tap to close) ──
          if (_isOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _close,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),

          // ── Mini FABs ──
          _buildMiniFab(
            index: 0,
            icon: Icons.warning_amber,
            label: 'Hazard',
            color: const Color(0xFFFFC107),
            onTap: () { _close(); widget.onReportHazard?.call(); },
          ),
          _buildMiniFab(
            index: 1,
            icon: Icons.visibility,
            label: 'Activity',
            color: const Color(0xFFFF9800),
            onTap: () { _close(); widget.onReportActivity?.call(); },
          ),
          _buildMiniFab(
            index: 2,
            icon: Icons.chat_bubble,
            label: 'Message',
            color: const Color(0xFF42A5F5),
            onTap: () { _close(); widget.onPostMessage?.call(); },
          ),
          _buildMiniFab(
            index: 3,
            icon: Icons.handshake,
            label: 'Resource',
            color: const Color(0xFF26A69A),
            onTap: () { _close(); widget.onShareResource?.call(); },
          ),

          // ── Main FAB ──
          Positioned(
            bottom: 0,
            right: 0,
            child: FloatingActionButton(
              heroTag: 'sentinel_report',
              onPressed: _toggle,
              backgroundColor: SojornColors.destructive,
              foregroundColor: SojornColors.basicWhite,
              elevation: 8,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, child) => Transform.rotate(
                  angle: _controller.value * math.pi / 4,
                  child: child,
                ),
                child: const Icon(Icons.add, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniFab({
    required int index,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final offsetY = 60.0 + (index * 48.0);
    return Positioned(
      bottom: offsetY,
      right: 4,
      child: FadeTransition(
        opacity: _controller,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.5),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _controller,
            curve: Interval(index * 0.1, 0.6 + index * 0.1, curve: Curves.easeOut),
          )),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Label chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xE6101020),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label, style: const TextStyle(color: SojornColors.basicWhite, fontSize: 11, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              // Mini button
              GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8)],
                  ),
                  child: Icon(icon, color: SojornColors.basicWhite, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
