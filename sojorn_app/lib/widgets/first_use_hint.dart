// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class FirstUseHint extends StatefulWidget {
  final String storageKey;
  final String text;
  final EdgeInsetsGeometry padding;
  final TextAlign textAlign;

  const FirstUseHint({
    super.key,
    required this.storageKey,
    required this.text,
    this.padding = const EdgeInsets.only(
      top: AppTheme.spacingLg,
      bottom: AppTheme.spacingSm,
    ),
    this.textAlign = TextAlign.left,
  });

  @override
  State<FirstUseHint> createState() => _FirstUseHintState();
}

class _FirstUseHintState extends State<FirstUseHint> {
  bool _shouldShow = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(widget.storageKey) ?? false;

    if (seen) return;

    if (!mounted) return;
    setState(() {
      _shouldShow = true;
      _visible = true;
    });

    await Future.delayed(const Duration(seconds: 3)); // Replaced AppTheme.durationHintHold
    if (!mounted) return;
    setState(() {
      _visible = false;
    });

    await Future.delayed(const Duration(milliseconds: 300)); // Replaced AppTheme.durationMedium
    await prefs.setBool(widget.storageKey, true);

    if (!mounted) return;
    setState(() {
      _shouldShow = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) return const SizedBox.shrink();

    return Padding(
      padding: widget.padding,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 300), // Replaced AppTheme.durationMedium
        child: Text(
          widget.text,
          style: AppTheme.textTheme.labelSmall?.copyWith( // Replaced bodySmall and textTertiary
            color: AppTheme.egyptianBlue,
          ),
          textAlign: widget.textAlign,
        ),
      ),
    );
  }
}