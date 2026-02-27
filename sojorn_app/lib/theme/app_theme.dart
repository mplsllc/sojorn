// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme_extensions.dart';
import 'tokens.dart';

enum AppThemeType {
  basic,
  pop,
}

class AppTheme {
  static AppThemeType _currentThemeType = AppThemeType.basic;
  static bool _isDark = false;

  static void setThemeType(AppThemeType type) {
    _currentThemeType = type;
  }

  static void setBrightness(Brightness brightness) {
    _isDark = brightness == Brightness.dark;
  }

  static bool get isDark => _isDark;

  static const Map<AppThemeType, SojornExt> _extensions = {
    AppThemeType.basic: SojornExt.basic,
    AppThemeType.pop: SojornExt.pop,
  };

  static const Map<AppThemeType, SojornExt> _darkExtensions = {
    AppThemeType.basic: SojornExt.basicDark,
    AppThemeType.pop: SojornExt.popDark,
  };

  static SojornExt get ext => _isDark
      ? _darkExtensions[_currentThemeType]!
      : _extensions[_currentThemeType]!;
  static SojornBrandColors get _brand => ext.brandColors;
  static SojornFlowLines get _lines => ext.flowLines;

  // Backward compatible color getters.
  static Color get navyBlue => _brand.navyBlue;
  static Color get navyText => _brand.navyText;
  static Color get egyptianBlue => _brand.egyptianBlue;
  static Color get brightNavy => _brand.brightNavy;
  static Color get royalPurple => _brand.royalPurple;
  static Color get ksuPurple => _brand.ksuPurple;
  static Color get queenPink => _brand.queenPink;
  static Color get queenPinkLight => _brand.queenPinkLight;
  static Color get scaffoldBg => _brand.scaffoldBg;
  static Color get cardSurface => _brand.cardSurface;
  static const Color white = SojornColors.basicWhite;

  // Semantic — brightness-aware
  static Color get error => _isDark ? SojornColors.darkError : SojornColors.error;
  static Color get destructive => _isDark ? SojornColors.darkError : SojornColors.destructive;
  static Color get success => _isDark ? SojornColors.darkSuccess : ksuPurple;
  static Color get warning => _isDark ? SojornColors.darkWarning : SojornColors.warning;
  static Color get info => _isDark ? SojornColors.darkInfo : SojornColors.info;

  // Dark surface layers (elevated, highest)
  static Color get surfaceElevated => _isDark ? SojornColors.darkSurfaceElevated : cardSurface;
  static Color get surfaceHighest => _isDark ? SojornColors.darkSurfaceHighest : cardSurface;

  // Dark border tokens
  static Color get borderSubtle => _isDark ? SojornColors.darkBorder : egyptianBlue;
  static Color get borderStrong => _isDark ? SojornColors.darkBorderStrong : egyptianBlue;

  // Input background
  static Color get inputBg => _isDark ? SojornColors.darkInputBg : cardSurface;

  // NSFW / Sensitive
  static const Color nsfwWarningBg = SojornColors.nsfwWarningBg;
  static const Color nsfwWarningBorder = SojornColors.nsfwWarningBorder;
  static const Color nsfwWarningIcon = SojornColors.nsfwWarningIcon;
  static const Color nsfwWarningText = SojornColors.nsfwWarningText;
  static const Color nsfwWarningSubText = SojornColors.nsfwWarningSubText;
  static const Color nsfwRevealText = SojornColors.nsfwRevealText;

  // Sponsored / Ad
  static const Color sponsoredBadgeBg = SojornColors.sponsoredBadgeBg;
  static const Color sponsoredBadgeText = SojornColors.sponsoredBadgeText;

  // Overlays
  static const Color overlayDark = SojornColors.overlayDark;
  static const Color overlayLight = SojornColors.overlayLight;
  static const Color mediaErrorBg = SojornColors.mediaErrorBg;
  static const Color mediaLoadingBg = SojornColors.mediaLoadingBg;

  // Trust Tiers
  static Color get tierEstablished => ext.trustTierColors.established;
  static Color get tierTrusted => ext.trustTierColors.trusted;
  static Color get tierNew => ext.trustTierColors.fresh;

  // Dimensions
  static const double spacingSm = SojornSpacing.sm;
  static const double spacingMd = SojornSpacing.md;
  static const double spacingLg = SojornSpacing.lg;
  static const double spacingXs = SojornSpacing.xs;
  static const double spacing2xs = SojornSpacing.xxs;

  static const double radiusSm = SojornRadii.sm;
  static const double radiusXs = SojornRadii.xs;
  static const double radiusMd = SojornRadii.md;
  static const double radiusMdValue = SojornRadii.md;
  static const double radiusLg = SojornRadii.lg;
  static const double radiusCard = SojornRadii.card;
  static const double radiusModal = SojornRadii.modal;
  static const double radiusFull = SojornRadii.full;

  // Text Colors - COLOR HIERARCHY: Content neutral, UI branded.
  static Color get textPrimary => navyText;
  static Color get textSecondary => _isDark ? SojornColors.darkTextSecondary : navyText;
  static Color get textTertiary => _isDark ? SojornColors.darkTextTertiary : navyText;
  static Color get textDisabled => _isDark ? SojornColors.darkTextTertiary : SojornColors.textDisabled;
  static const Color textOnAccent = SojornColors.textOnAccent;
  static Color get border => egyptianBlue;

  // Post Content - Neutral for contrast with purple UI.
  static Color get postContent => _isDark ? SojornColors.darkPostContent : SojornColors.postContent;
  static Color get postContentLight => _isDark ? SojornColors.darkPostContentLight : SojornColors.postContentLight;

  // Lines
  static const double borderWidth = SojornLines.border;
  static const double dividerThickness = SojornLines.dividerStrong;
  static const double flowLineWidth = SojornLines.flow;

  // Post Specific Spacing
  static const double spacingPostShort = SojornSpacing.postShort;
  static const double spacingPostMedium = SojornSpacing.postMedium;
  static const double spacingPostLong = SojornSpacing.postLong;

  // Typography
  static TextTheme get textTheme => _buildTextTheme(_brand);

  // Backward Compat Getters
  static TextStyle get postBody => textTheme.bodyLarge!;
  static TextStyle get postBodyShort => textTheme.bodyLarge!.copyWith(fontSize: 22);
  static TextStyle get postBodyLong => textTheme.bodyLarge!.copyWith(fontSize: 18);
  static TextStyle get postBodyReflective => textTheme.bodyLarge!.copyWith(
        fontStyle: FontStyle.italic,
        color: ksuPurple,
      );

  // Text Style Getters
  static TextStyle get bodyMedium => textTheme.bodyMedium!;
  static TextStyle get bodyLarge => textTheme.bodyLarge!;
  static TextStyle get headlineMedium => textTheme.headlineMedium!;
  static TextStyle get headlineSmall => textTheme.headlineSmall!;
  static TextStyle get labelLarge => textTheme.labelLarge!;
  static TextStyle get labelMedium => textTheme.labelMedium!;
  static TextStyle get labelSmall => textTheme.labelSmall!;

  // Theme Data
  static ThemeData get lightTheme => themeFor(_currentThemeType);
  static ThemeData get darkTheme => darkThemeFor(_currentThemeType);

  static ThemeData themeFor(AppThemeType type) {
    final ext = _extensions[type]!;
    return _buildTheme(ext, Brightness.light);
  }

  static ThemeData darkThemeFor(AppThemeType type) {
    final ext = _darkExtensions[type]!;
    return _buildTheme(ext, Brightness.dark);
  }

  static ThemeData _buildTheme(SojornExt ext, [Brightness brightness = Brightness.light]) {
    final brand = ext.brandColors;
    final lines = ext.flowLines;
    final textTheme = _buildTextTheme(brand);

    final isDarkBrand = brand.scaffoldBg == SojornColors.darkScaffoldBg;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: brand.scaffoldBg,
      primaryColor: brand.navyBlue,
      cardColor: brand.cardSurface,
      canvasColor: brand.scaffoldBg,
      dialogTheme: DialogThemeData(
        backgroundColor: isDarkBrand ? SojornColors.darkSurfaceElevated : brand.cardSurface,
      ),
      colorScheme: _buildColorScheme(brand, brightness),
      textTheme: textTheme,
      fontFamily: GoogleFonts.literata().fontFamily,
      fontFamilyFallback: const ['Apple Color Emoji', 'Segoe UI Emoji', 'Noto Color Emoji'],
      appBarTheme: _buildAppBarTheme(brand, textTheme, lines, brightness),
      cardTheme: _buildCardTheme(brand, lines),
      elevatedButtonTheme: _buildElevatedButtonTheme(brand),
      textButtonTheme: _buildTextButtonTheme(brand),
      bottomNavigationBarTheme: _buildBottomNavTheme(brand, ext.options),
      floatingActionButtonTheme: _buildFabTheme(brand, ext.options),
      dividerTheme: _buildDividerTheme(brand, lines),
      inputDecorationTheme: _buildInputTheme(brand, lines),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDarkBrand ? SojornColors.darkSurfaceElevated : brand.cardSurface,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDarkBrand ? SojornColors.darkSurfaceElevated : brand.cardSurface,
      ),
      extensions: <ThemeExtension<dynamic>>[ext],
    );
  }

  static TextTheme _buildTextTheme(SojornBrandColors brand) {
    final isDarkBrand = brand.scaffoldBg == SojornColors.darkScaffoldBg;
    return GoogleFonts.literataTextTheme().copyWith(
      bodyLarge: GoogleFonts.literata(
        fontSize: 17,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: isDarkBrand ? SojornColors.darkPostContent : SojornColors.postContent,
      ),
      bodyMedium: GoogleFonts.literata(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: isDarkBrand ? SojornColors.darkPostContentLight : SojornColors.postContentLight,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: brand.egyptianBlue,
        letterSpacing: 0.2,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: brand.brightNavy,
        letterSpacing: 0,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: brand.navyBlue,
      ),
      headlineSmall: GoogleFonts.literata(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: brand.navyBlue,
        letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.literata(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: brand.navyBlue,
        letterSpacing: 0,
      ),
    );
  }

  static ColorScheme _buildColorScheme(SojornBrandColors brand, [Brightness brightness = Brightness.light]) {
    if (brightness == Brightness.dark) {
      return ColorScheme.dark(
        primary: brand.navyBlue,
        secondary: brand.brightNavy,
        tertiary: brand.royalPurple,
        surface: brand.cardSurface,
        onSurface: brand.navyText,
        error: SojornColors.error,
      );
    }
    return ColorScheme.light(
      primary: brand.navyBlue,
      secondary: brand.brightNavy,
      tertiary: brand.royalPurple,
      surface: brand.cardSurface,
      onSurface: brand.navyText,
      error: SojornColors.error,
    );
  }

  static AppBarTheme _buildAppBarTheme(
    SojornBrandColors brand,
    TextTheme textTheme,
    SojornFlowLines lines, [
    Brightness brightness = Brightness.light,
  ]) {
    final isDarkBrand = brand.scaffoldBg == SojornColors.darkScaffoldBg;
    final borderColor = isDarkBrand ? SojornColors.darkBorder : brand.egyptianBlue;
    return AppBarTheme(
      backgroundColor: brand.cardSurface,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: brand.navyBlue),
      titleTextStyle: textTheme.headlineSmall,
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      shape: Border(
        bottom: BorderSide(color: borderColor, width: lines.appBarBorder),
      ),
    );
  }

  static CardThemeData _buildCardTheme(SojornBrandColors brand, SojornFlowLines lines) {
    final isDarkBrand = brand.scaffoldBg == SojornColors.darkScaffoldBg;
    final borderColor = isDarkBrand ? SojornColors.darkBorder : brand.egyptianBlue;
    return CardThemeData(
      color: brand.cardSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SojornRadii.lg),
        side: BorderSide(color: borderColor, width: lines.cardBorder),
      ),
    );
  }

  static ElevatedButtonThemeData _buildElevatedButtonTheme(SojornBrandColors brand) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: brand.brightNavy,
        foregroundColor: SojornColors.textOnAccent,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: SojornSpacing.lg,
          vertical: SojornSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SojornRadii.md),
        ),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold),
      ),
    );
  }

  static TextButtonThemeData _buildTextButtonTheme(SojornBrandColors brand) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: brand.egyptianBlue,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
    );
  }

  static BottomNavigationBarThemeData _buildBottomNavTheme(
    SojornBrandColors brand,
    SojornThemeOptions options,
  ) {
    final isDarkBrand = brand.scaffoldBg == SojornColors.darkScaffoldBg;
    return BottomNavigationBarThemeData(
      backgroundColor: brand.cardSurface,
      selectedItemColor: brand.royalPurple,
      unselectedItemColor: isDarkBrand ? SojornColors.darkTextTertiary : SojornColors.bottomNavUnselected,
      type: BottomNavigationBarType.fixed,
      showSelectedLabels: options.showBottomNavLabels,
      showUnselectedLabels: options.showBottomNavLabels,
      elevation: options.bottomNavElevation,
    );
  }

  static FloatingActionButtonThemeData _buildFabTheme(
    SojornBrandColors brand,
    SojornThemeOptions options,
  ) {
    return FloatingActionButtonThemeData(
      backgroundColor: brand.brightNavy,
      foregroundColor: SojornColors.textOnAccent,
      elevation: options.fabElevation,
      shape: options.fabShape,
    );
  }

  static DividerThemeData _buildDividerTheme(
    SojornBrandColors brand,
    SojornFlowLines lines,
  ) {
    final isDarkBrand = brand.scaffoldBg == SojornColors.darkScaffoldBg;
    return DividerThemeData(
      color: isDarkBrand ? SojornColors.darkBorder : brand.queenPink,
      thickness: lines.divider,
      space: SojornSpacing.lg,
    );
  }

  static InputDecorationTheme _buildInputTheme(
    SojornBrandColors brand,
    SojornFlowLines lines,
  ) {
    final isDarkBrand = brand.scaffoldBg == SojornColors.darkScaffoldBg;
    final fillColor = isDarkBrand ? SojornColors.darkInputBg : brand.cardSurface;
    final borderColor = isDarkBrand ? SojornColors.darkBorder : brand.egyptianBlue;
    final focusColor = isDarkBrand ? SojornColors.darkBrand : brand.royalPurple;
    return InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.all(SojornSpacing.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SojornRadii.md),
        borderSide: BorderSide(color: borderColor, width: lines.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SojornRadii.md),
        borderSide: BorderSide(color: borderColor, width: lines.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SojornRadii.md),
        borderSide: BorderSide(color: focusColor, width: lines.inputFocusBorder),
      ),
    );
  }
}
