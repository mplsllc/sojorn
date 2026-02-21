// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;
  final PreferredSizeWidget? customAppBar;
  final bool showAppBar;
  final PreferredSizeWidget? bottom;

  const AppScaffold({
    super.key,
    this.title = '',
    required this.body,
    this.leading,
    this.actions,
    this.centerTitle = true,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
    this.customAppBar,
    this.showAppBar = true,
    this.bottom,
  });

  // Responsive breakpoints and margins (moved from AppTheme)
  static const double _breakpointTablet = 600.0;
  static const double _breakpointDesktop = 1200.0;
  static const double _marginMobile = AppTheme.spacingMd; // 16.0
  static const double _marginTablet = AppTheme.spacingLg; // 24.0
  static const double _marginDesktop = AppTheme.spacingLg * 2; // 48.0
  static const double _maxContentWidth = 720.0;

  double _horizontalPadding(double width) {
    if (width < _breakpointTablet) {
      return _marginMobile;
    }
    if (width < _breakpointDesktop) {
      return _marginTablet;
    }
    return _marginDesktop;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.queenPinkLight,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      appBar:
          showAppBar ? (customAppBar ?? _buildDefaultAppBar(context)) : null,
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = _horizontalPadding(constraints.maxWidth);
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _maxContentWidth,
                  ),
                  child: body,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildDefaultAppBar(BuildContext context) {
    return AppBar(
      title: title.isEmpty
          ? Image.asset('assets/images/toplogo.png', height: 40)
          : Text(title),
      centerTitle: centerTitle,
      leading: leading ?? _buildBackButton(context),
      actions: actions,
      elevation: 0,
      backgroundColor: AppTheme.queenPinkLight,
      iconTheme: IconThemeData(color: AppTheme.navyBlue),
      bottom: bottom,
    );
}

  Widget? _buildBackButton(BuildContext context) {
    return Navigator.canPop(context)
        ? IconButton(
            icon: Icon(Icons.arrow_back, color: AppTheme.navyBlue),
            onPressed: () => Navigator.of(context).pop(),
          )
        : null;
  }
}
