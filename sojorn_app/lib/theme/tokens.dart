// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';

class SojornColors {
  const SojornColors._();

  // ── Basic theme palette ──────────────────────────────
  static const Color basicNavyBlue = Color(0xFF000383);
  static const Color basicNavyText = Color(0xFF000383);
  static const Color basicEgyptianBlue = Color(0xFF0E38AE);
  static const Color basicBrightNavy = Color(0xFF1974D1);
  static const Color basicRoyalPurple = Color(0xFF7751A8);
  static const Color basicKsuPurple = Color(0xFF512889);
  static const Color basicQueenPink = Color(0xFFE5C0DD);
  static const Color basicQueenPinkLight = Color(0xFFF9F2F7);
  static const Color basicWhite = Color(0xFFFFFFFF);
  static const Color basicBlack = Color(0xFF000000);

  // ── Pop theme palette ────────────────────────────────
  static const Color popNavyBlue = Color(0xFF000383);
  static const Color popNavyText = Color(0xFF0D1050);
  static const Color popEgyptianBlue = Color(0xFF0E38AE);
  static const Color popBrightNavy = Color(0xFF1974D1);
  static const Color popRoyalPurple = Color(0xFF7751A8);
  static const Color popKsuPurple = Color(0xFF512889);
  static const Color popScaffoldBg = Color(0xFFF9F6F9);
  static const Color popCardSurface = Color(0xFFFFFFFF);
  static const Color popHighlight = Color(0xFFE5C0DD);

  // ── Dark theme palette ──────────────────────────────
  // Indigo-tinted dark — never pure black, warm enough for extended reading.
  // Backgrounds (layered depth)
  static const Color darkScaffoldBg = Color(0xFF13141F);       // bg0 — deepest, app background
  static const Color darkCardSurface = Color(0xFF1A1B2E);      // bg1 — primary surface, cards
  static const Color darkSurfaceElevated = Color(0xFF222337);  // bg2 — sheets, modals, compose
  static const Color darkSurfaceHighest = Color(0xFF2A2B45);   // bg3 — dropdowns, tooltips, hover

  // Text (never pure white)
  static const Color darkNavyText = Color(0xFFE8E9F0);         // text1 — primary, ~12:1 on bg1
  static const Color darkTextSecondary = Color(0xFFA0A3B5);    // text2 — timestamps, handles
  static const Color darkTextTertiary = Color(0xFF6B6E82);     // text3 — placeholders, disabled

  // Borders & dividers
  static const Color darkBorder = Color(0xFF2E3050);           // border1 — subtle dividers
  static const Color darkBorderStrong = Color(0xFF3A3C5C);     // border2 — inputs, active elements

  // Brand indigo — unchanged from light, pops better on dark
  static const Color darkBrand = Color(0xFF6366F1);            // primary accent
  static const Color darkBrandMuted = Color(0xFF4F51C0);       // hover/pressed state

  // Brand colors mapped to existing fields
  static const Color darkEgyptianBlue = Color(0xFF6366F1);     // brand indigo
  static const Color darkBrightNavy = Color(0xFF5558E0);       // pressed/hover variant
  static const Color darkRoyalPurple = Color(0xFF9B8BDB);      // softened for dark
  static const Color darkKsuPurple = Color(0xFF8B5FC7);
  static const Color darkQueenPink = Color(0xFF3D2A38);
  static const Color darkQueenPinkLight = Color(0xFF1A1520);

  // Semantic (adjusted for dark backgrounds — brighter than light mode)
  static const Color darkWarning = Color(0xFFD4940C);          // lifted from #AD7A0A
  static const Color darkInfo = Color(0xFF5B9FE8);             // brighter blue
  static const Color darkError = Color(0xFFE85B5B);            // brighter red
  static const Color darkSuccess = Color(0xFF4ADE80);          // online indicators, confirmations

  // Input
  static const Color darkInputBg = Color(0xFF1E1F33);

  // Post content on dark
  static const Color darkPostContent = Color(0xFFE8E9F0);      // same as text1
  static const Color darkPostContentLight = Color(0xFFA0A3B5); // same as text2

  // ── Semantic ─────────────────────────────────────────
  static const Color error = Color(0xFFD32F2F);
  static const Color destructive = Color(0xFFD32F2F);
  static const Color warning = Color(0xFFAD7A0A);          // was #FBC02D (1.6:1 on white — WCAG fail); now ~5.7:1 on white (AA)
  static const Color info = Color(0xFF0B6FCC);              // was #2196F3 (3.5:1 on white — WCAG fail); now ~4.6:1 on white (AA)
  static const Color textDisabled = Color(0xFF707070);      // was #9E9E9E (3.5:1 on white — WCAG fail); now ~5.0:1 on white (AA)
  static const Color textOnAccent = Color(0xFFFFFFFF);

  // ── Post content ─────────────────────────────────────
  static const Color postContent = Color(0xFF1A1A1A);
  static const Color postContentLight = Color(0xFF4A4A4A);

  // ── Navigation ───────────────────────────────────────
  static const Color bottomNavUnselected = Color(0xFF6B7082);  // was #9EA3B0 (3.3:1 on white — WCAG fail); now ~4.7:1 on white (AA)

  // ── Trust tiers ──────────────────────────────────────
  static const Color tierNew = Color(0xFF9E9E9E);

  // ── NSFW / Sensitive content ─────────────────────────
  static const Color nsfwWarningBg = Color(0x26EF6C00);       // amber.800 @ 15%
  static const Color nsfwWarningBorder = Color(0x4DF57C00);   // amber.700 @ 30%
  static const Color nsfwWarningIcon = Color(0xFFF57C00);     // amber.700
  static const Color nsfwWarningText = Color(0xFFF57C00);     // amber.700
  static const Color nsfwWarningSubText = Color(0xFFFB8C00);  // amber.600
  static const Color nsfwRevealText = Color(0xCCFB8C00);      // amber.600 @ 80%

  // ── Sponsored / Ad ───────────────────────────────────
  static const Color sponsoredBadgeBg = Color(0x1A7751A8);    // royalPurple @ 10%
  static const Color sponsoredBadgeText = Color(0xB37751A8);  // royalPurple @ 70%

  // ── Overlays ─────────────────────────────────────────
  static const Color overlayDark = Color(0x80000000);          // black @ 50%
  static const Color overlayLight = Color(0x4DFFFFFF);         // white @ 30%
  static const Color overlayScrim = Color(0x33000000);         // black @ 20%
  static const Color transparent = Color(0x00000000);

  // ── Surface states ───────────────────────────────────
  static const Color surfacePressed = Color(0x14000383);       // navyBlue @ 8%
  static const Color surfaceHover = Color(0x0A000383);         // navyBlue @ 4%
  static const Color mediaErrorBg = Color(0x4DD32F2F);         // error @ 30%
  static const Color mediaLoadingBg = Color(0x4DE5C0DD);       // queenPink @ 30%

  // ── Feed palettes ────────────────────────────────────
  static const Color feedNavyTop = Color(0xFF0B1023);
  static const Color feedNavyBottom = Color(0xFF1B2340);
  static const Color feedNavyPanel = Color(0xFF0E1328);
  static const Color feedNavyText = Color(0xFFF8FAFF);
  static const Color feedNavySubText = Color(0xFFB9C3E6);
  static const Color feedNavyAccent = Color(0xFF70A7FF);

  static const Color feedForestTop = Color(0xFF0E1A16);
  static const Color feedForestBottom = Color(0xFF1E3A2D);
  static const Color feedForestPanel = Color(0xFF12261F);
  static const Color feedForestText = Color(0xFFF5FFF8);
  static const Color feedForestSubText = Color(0xFFB7D7C6);
  static const Color feedForestAccent = Color(0xFF5FD7A1);

  static const Color feedRoseTop = Color(0xFF1B0E16);
  static const Color feedRoseBottom = Color(0xFF3A1B2B);
  static const Color feedRosePanel = Color(0xFF24101A);
  static const Color feedRoseText = Color(0xFFFFF6F9);
  static const Color feedRoseSubText = Color(0xFFE0B9C6);
  static const Color feedRoseAccent = Color(0xFFF28FB3);

  static const Color feedSkyTop = Color(0xFF0B1720);
  static const Color feedSkyBottom = Color(0xFF193547);
  static const Color feedSkyPanel = Color(0xFF10212D);
  static const Color feedSkyText = Color(0xFFEFF7FF);
  static const Color feedSkySubText = Color(0xFFAFC6D9);
  static const Color feedSkyAccent = Color(0xFF6FD3FF);

  static const Color feedAmberTop = Color(0xFF201A12);
  static const Color feedAmberBottom = Color(0xFF3A2C1B);
  static const Color feedAmberPanel = Color(0xFF221B13);
  static const Color feedAmberText = Color(0xFFFFF7ED);
  static const Color feedAmberSubText = Color(0xFFD9C8AE);
  static const Color feedAmberAccent = Color(0xFFFFC074);
}

class SojornSpacing {
  const SojornSpacing._();

  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;

  // Granular steps for fine-tuning
  static const double s6 = 6.0;
  static const double s8 = 8.0;

  static const double postShort = 16.0;
  static const double postMedium = 24.0;
  static const double postLong = 32.0;

  // Card-level margins
  static const double cardGap = 16.0;
  static const double cardGapThread = 4.0;
}

class SojornRadii {
  const SojornRadii._();

  static const double xs = 2.0;
  static const double sm = 4.0;
  static const double md = 8.0;
  static const double lg = 12.0;
  static const double card = 16.0;
  static const double xl = 20.0;
  static const double modal = 24.0;
  static const double full = 36.0;
}

class SojornLines {
  const SojornLines._();

  static const double borderThin = 1.0;
  static const double border = 1.5;
  static const double borderStrong = 2.0;
  static const double divider = 1.0;
  static const double dividerStrong = 2.0;
  static const double flow = 3.0;
}

class SojornNav {
  const SojornNav._();

  // Shell bottom nav
  static const double bottomBarHeight = 58.0;
  static const double bottomBarIconSize = 24.0;
  static const double bottomBarVerticalPadding = 0.0;
  static const double bottomFabGap = 48.0;
  static const double bottomBarLabelSize = 11.0;
  static const double bottomBarLabelTopGap = 2.0;

  // Beacon top tab icons
  static const double beaconTabIconSize = 18.0;
}

class SojornBreakpoints {
  const SojornBreakpoints._();

  static const double mobile = 600.0;
  static const double tablet = 900.0;
  static const double desktop = 1200.0;

  static const double maxContentWidth = 640.0;
  static const double sidebarWidth = 320.0;
  static const double navRailWidth = 72.0;
  static const double navRailExtended = 200.0;

  static bool isMobile(double w) => w < mobile;
  static bool isTablet(double w) => w >= mobile && w < tablet;
  static bool isDesktop(double w) => w >= tablet;
  static bool isWideDesktop(double w) => w >= desktop;
}
