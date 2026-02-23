// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

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

  double _horizontalPadding(double width) {
    if (SojornBreakpoints.isMobile(width)) return AppTheme.spacingMd;
    if (width < SojornBreakpoints.desktop) return AppTheme.spacingLg;
    return AppTheme.spacingLg * 2;
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
                    maxWidth: SojornBreakpoints.maxContentWidth,
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
