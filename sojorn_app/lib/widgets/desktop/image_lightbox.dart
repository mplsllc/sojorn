// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../theme/tokens.dart';
import '../media/signed_media_image.dart';

class ImageLightbox extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String? authorName;
  final String? caption;
  final DateTime? date;
  final VoidCallback onClose;

  const ImageLightbox({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.authorName,
    this.caption,
    this.date,
    required this.onClose,
  });

  @override
  State<ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends State<ImageLightbox> {
  late int _currentIndex;
  late TransformationController _transformationController;
  final FocusNode _focusNode = FocusNode();
  bool _isHovered = false;

  bool get _hasMultipleImages => widget.imageUrls.length > 1;
  bool get _canGoPrev => _currentIndex > 0;
  bool get _canGoNext => _currentIndex < widget.imageUrls.length - 1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _transformationController = TransformationController();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _goToPrev() {
    if (!_canGoPrev) return;
    setState(() {
      _currentIndex--;
      _resetZoom();
    });
  }

  void _goToNext() {
    if (!_canGoNext) return;
    setState(() {
      _currentIndex++;
      _resetZoom();
    });
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goToPrev();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goToNext();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onClose,
          child: Material(
            color: Colors.black.withValues(alpha: 0.85),
            child: Stack(
              children: [
                // ── Centered image with zoom/pan ──────────────
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {}, // absorb taps on image area
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeIn,
                          switchOutCurve: Curves.easeOut,
                          child: SignedMediaImage(
                            key: ValueKey(widget.imageUrls[_currentIndex]),
                            url: widget.imageUrls[_currentIndex],
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Close button (top-right) ─────────────────
                Positioned(
                  top: 16,
                  right: 16,
                  child: _LightboxIconButton(
                    icon: Icons.close,
                    onTap: widget.onClose,
                    tooltip: 'Close',
                  ),
                ),

                // ── Left arrow ───────────────────────────────
                if (_hasMultipleImages && _canGoPrev)
                  Positioned(
                    left: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: _LightboxIconButton(
                          icon: Icons.chevron_left,
                          onTap: _goToPrev,
                          tooltip: 'Previous image',
                        ),
                      ),
                    ),
                  ),

                // ── Right arrow ──────────────────────────────
                if (_hasMultipleImages && _canGoNext)
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: _LightboxIconButton(
                          icon: Icons.chevron_right,
                          onTap: _goToNext,
                          tooltip: 'Next image',
                        ),
                      ),
                    ),
                  ),

                // ── Bottom metadata bar ──────────────────────
                if (widget.authorName != null || widget.caption != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: Center(
                      child: _MetadataBar(
                        authorName: widget.authorName,
                        caption: widget.caption,
                        date: widget.date,
                      ),
                    ),
                  ),

                // ── Page indicator ───────────────────────────
                if (_hasMultipleImages)
                  Positioned(
                    top: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(SojornRadii.full),
                        ),
                        child: Text(
                          '${_currentIndex + 1} / ${widget.imageUrls.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Arrow / Close button ──────────────────────────────────────

class _LightboxIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _LightboxIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}

// ── Bottom metadata bar ───────────────────────────────────────

class _MetadataBar extends StatelessWidget {
  final String? authorName;
  final String? caption;
  final DateTime? date;

  const _MetadataBar({
    this.authorName,
    this.caption,
    this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 600),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(SojornRadii.lg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author + date row
          if (authorName != null)
            Row(
              children: [
                Flexible(
                  child: Text(
                    authorName!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (date != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    timeago.format(date!),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),

          // Date on its own row when there's no author
          if (authorName == null && date != null)
            Text(
              timeago.format(date!),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),

          // Caption
          if (caption != null) ...[
            if (authorName != null || date != null)
              const SizedBox(height: 6),
            Text(
              caption!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
