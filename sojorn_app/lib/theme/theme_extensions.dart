import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'tokens.dart';

@immutable
class SojornBrandColors {
  final Color navyBlue;
  final Color navyText;
  final Color egyptianBlue;
  final Color brightNavy;
  final Color royalPurple;
  final Color ksuPurple;
  final Color queenPink;
  final Color queenPinkLight;
  final Color scaffoldBg;
  final Color cardSurface;

  const SojornBrandColors({
    required this.navyBlue,
    required this.navyText,
    required this.egyptianBlue,
    required this.brightNavy,
    required this.royalPurple,
    required this.ksuPurple,
    required this.queenPink,
    required this.queenPinkLight,
    required this.scaffoldBg,
    required this.cardSurface,
  });

  SojornBrandColors lerp(SojornBrandColors other, double t) {
    return SojornBrandColors(
      navyBlue: Color.lerp(navyBlue, other.navyBlue, t)!,
      navyText: Color.lerp(navyText, other.navyText, t)!,
      egyptianBlue: Color.lerp(egyptianBlue, other.egyptianBlue, t)!,
      brightNavy: Color.lerp(brightNavy, other.brightNavy, t)!,
      royalPurple: Color.lerp(royalPurple, other.royalPurple, t)!,
      ksuPurple: Color.lerp(ksuPurple, other.ksuPurple, t)!,
      queenPink: Color.lerp(queenPink, other.queenPink, t)!,
      queenPinkLight: Color.lerp(queenPinkLight, other.queenPinkLight, t)!,
      scaffoldBg: Color.lerp(scaffoldBg, other.scaffoldBg, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
    );
  }
}

@immutable
class SojornTrustTierColors {
  final Color established;
  final Color trusted;
  final Color fresh;

  const SojornTrustTierColors({
    required this.established,
    required this.trusted,
    required this.fresh,
  });

  SojornTrustTierColors lerp(SojornTrustTierColors other, double t) {
    return SojornTrustTierColors(
      established: Color.lerp(established, other.established, t)!,
      trusted: Color.lerp(trusted, other.trusted, t)!,
      fresh: Color.lerp(fresh, other.fresh, t)!,
    );
  }
}

@immutable
class SojornFlowLines {
  final double appBarBorder;
  final double cardBorder;
  final double inputBorder;
  final double inputFocusBorder;
  final double divider;
  final double flow;

  const SojornFlowLines({
    required this.appBarBorder,
    required this.cardBorder,
    required this.inputBorder,
    required this.inputFocusBorder,
    required this.divider,
    required this.flow,
  });

  SojornFlowLines lerp(SojornFlowLines other, double t) {
    return SojornFlowLines(
      appBarBorder: lerpDouble(appBarBorder, other.appBarBorder, t)!,
      cardBorder: lerpDouble(cardBorder, other.cardBorder, t)!,
      inputBorder: lerpDouble(inputBorder, other.inputBorder, t)!,
      inputFocusBorder: lerpDouble(inputFocusBorder, other.inputFocusBorder, t)!,
      divider: lerpDouble(divider, other.divider, t)!,
      flow: lerpDouble(flow, other.flow, t)!,
    );
  }
}

@immutable
class SojornThemeOptions {
  final bool showBottomNavLabels;
  final double bottomNavElevation;
  final double fabElevation;
  final ShapeBorder? fabShape;

  const SojornThemeOptions({
    required this.showBottomNavLabels,
    required this.bottomNavElevation,
    required this.fabElevation,
    required this.fabShape,
  });

  SojornThemeOptions lerp(SojornThemeOptions other, double t) {
    return SojornThemeOptions(
      showBottomNavLabels: t < 0.5 ? showBottomNavLabels : other.showBottomNavLabels,
      bottomNavElevation: lerpDouble(bottomNavElevation, other.bottomNavElevation, t)!,
      fabElevation: lerpDouble(fabElevation, other.fabElevation, t)!,
      fabShape: ShapeBorder.lerp(fabShape, other.fabShape, t),
    );
  }
}

@immutable
class SojornFeedPalette {
  final Color backgroundTop;
  final Color backgroundBottom;
  final Color panelColor;
  final Color textColor;
  final Color subTextColor;
  final Color accentColor;

  const SojornFeedPalette({
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.panelColor,
    required this.textColor,
    required this.subTextColor,
    required this.accentColor,
  });

  SojornFeedPalette lerp(SojornFeedPalette other, double t) {
    return SojornFeedPalette(
      backgroundTop: Color.lerp(backgroundTop, other.backgroundTop, t)!,
      backgroundBottom: Color.lerp(backgroundBottom, other.backgroundBottom, t)!,
      panelColor: Color.lerp(panelColor, other.panelColor, t)!,
      textColor: Color.lerp(textColor, other.textColor, t)!,
      subTextColor: Color.lerp(subTextColor, other.subTextColor, t)!,
      accentColor: Color.lerp(accentColor, other.accentColor, t)!,
    );
  }
}

@immutable
class SojornFeedPalettes {
  final List<SojornFeedPalette> presets;

  const SojornFeedPalettes({required this.presets});

  static const SojornFeedPalettes defaultPresets = SojornFeedPalettes(
    presets: [
      SojornFeedPalette(
        backgroundTop: SojornColors.feedNavyTop,
        backgroundBottom: SojornColors.feedNavyBottom,
        panelColor: SojornColors.feedNavyPanel,
        textColor: SojornColors.feedNavyText,
        subTextColor: SojornColors.feedNavySubText,
        accentColor: SojornColors.feedNavyAccent,
      ),
      SojornFeedPalette(
        backgroundTop: SojornColors.feedForestTop,
        backgroundBottom: SojornColors.feedForestBottom,
        panelColor: SojornColors.feedForestPanel,
        textColor: SojornColors.feedForestText,
        subTextColor: SojornColors.feedForestSubText,
        accentColor: SojornColors.feedForestAccent,
      ),
      SojornFeedPalette(
        backgroundTop: SojornColors.feedRoseTop,
        backgroundBottom: SojornColors.feedRoseBottom,
        panelColor: SojornColors.feedRosePanel,
        textColor: SojornColors.feedRoseText,
        subTextColor: SojornColors.feedRoseSubText,
        accentColor: SojornColors.feedRoseAccent,
      ),
      SojornFeedPalette(
        backgroundTop: SojornColors.feedSkyTop,
        backgroundBottom: SojornColors.feedSkyBottom,
        panelColor: SojornColors.feedSkyPanel,
        textColor: SojornColors.feedSkyText,
        subTextColor: SojornColors.feedSkySubText,
        accentColor: SojornColors.feedSkyAccent,
      ),
      SojornFeedPalette(
        backgroundTop: SojornColors.feedAmberTop,
        backgroundBottom: SojornColors.feedAmberBottom,
        panelColor: SojornColors.feedAmberPanel,
        textColor: SojornColors.feedAmberText,
        subTextColor: SojornColors.feedAmberSubText,
        accentColor: SojornColors.feedAmberAccent,
      ),
    ],
  );

  SojornFeedPalette forId(String id) {
    final index = id.hashCode.abs() % presets.length;
    return presets[index];
  }

  SojornFeedPalettes lerp(SojornFeedPalettes other, double t) {
    if (presets.length != other.presets.length) {
      return t < 0.5 ? this : other;
    }

    return SojornFeedPalettes(
      presets: List<SojornFeedPalette>.generate(
        presets.length,
        (index) => presets[index].lerp(other.presets[index], t),
      ),
    );
  }
}

@immutable
class SojornExt extends ThemeExtension<SojornExt> {
  final SojornBrandColors brandColors;
  final SojornTrustTierColors trustTierColors;
  final SojornFlowLines flowLines;
  final SojornFeedPalettes feedPalettes;
  final SojornThemeOptions options;

  const SojornExt({
    required this.brandColors,
    required this.trustTierColors,
    required this.flowLines,
    required this.feedPalettes,
    required this.options,
  });

  static const SojornExt basic = SojornExt(
    brandColors: SojornBrandColors(
      navyBlue: SojornColors.basicNavyBlue,
      navyText: SojornColors.basicNavyText,
      egyptianBlue: SojornColors.basicEgyptianBlue,
      brightNavy: SojornColors.basicBrightNavy,
      royalPurple: SojornColors.basicRoyalPurple,
      ksuPurple: SojornColors.basicKsuPurple,
      queenPink: SojornColors.basicQueenPink,
      queenPinkLight: SojornColors.basicQueenPinkLight,
      scaffoldBg: SojornColors.basicQueenPinkLight,
      cardSurface: SojornColors.basicWhite,
    ),
    trustTierColors: SojornTrustTierColors(
      established: SojornColors.basicEgyptianBlue,
      trusted: SojornColors.basicRoyalPurple,
      fresh: SojornColors.tierNew,
    ),
    flowLines: SojornFlowLines(
      appBarBorder: SojornLines.border,
      cardBorder: SojornLines.borderThin,
      inputBorder: SojornLines.borderThin,
      inputFocusBorder: SojornLines.borderStrong,
      divider: SojornLines.divider,
      flow: SojornLines.flow,
    ),
    feedPalettes: SojornFeedPalettes.defaultPresets,
    options: SojornThemeOptions(
      showBottomNavLabels: true,
      bottomNavElevation: 0,
      fabElevation: 6,
      fabShape: null,
    ),
  );

  static const SojornExt pop = SojornExt(
    brandColors: SojornBrandColors(
      navyBlue: SojornColors.popNavyBlue,
      navyText: SojornColors.popNavyText,
      egyptianBlue: SojornColors.popEgyptianBlue,
      brightNavy: SojornColors.popBrightNavy,
      royalPurple: SojornColors.popRoyalPurple,
      ksuPurple: SojornColors.popKsuPurple,
      queenPink: SojornColors.popHighlight,
      queenPinkLight: SojornColors.popScaffoldBg,
      scaffoldBg: SojornColors.popScaffoldBg,
      cardSurface: SojornColors.popCardSurface,
    ),
    trustTierColors: SojornTrustTierColors(
      established: SojornColors.popEgyptianBlue,
      trusted: SojornColors.popRoyalPurple,
      fresh: SojornColors.tierNew,
    ),
    flowLines: SojornFlowLines(
      appBarBorder: SojornLines.borderStrong,
      cardBorder: SojornLines.borderThin,
      inputBorder: SojornLines.borderThin,
      inputFocusBorder: SojornLines.borderStrong,
      divider: SojornLines.divider,
      flow: SojornLines.flow,
    ),
    feedPalettes: SojornFeedPalettes.defaultPresets,
    options: SojornThemeOptions(
      showBottomNavLabels: false,
      bottomNavElevation: 10,
      fabElevation: 4,
      fabShape: const CircleBorder(),
    ),
  );

  @override
  SojornExt copyWith({
    SojornBrandColors? brandColors,
    SojornTrustTierColors? trustTierColors,
    SojornFlowLines? flowLines,
    SojornFeedPalettes? feedPalettes,
    SojornThemeOptions? options,
  }) {
    return SojornExt(
      brandColors: brandColors ?? this.brandColors,
      trustTierColors: trustTierColors ?? this.trustTierColors,
      flowLines: flowLines ?? this.flowLines,
      feedPalettes: feedPalettes ?? this.feedPalettes,
      options: options ?? this.options,
    );
  }

  @override
  SojornExt lerp(ThemeExtension<SojornExt>? other, double t) {
    if (other is! SojornExt) {
      return this;
    }

    return SojornExt(
      brandColors: brandColors.lerp(other.brandColors, t),
      trustTierColors: trustTierColors.lerp(other.trustTierColors, t),
      flowLines: flowLines.lerp(other.flowLines, t),
      feedPalettes: feedPalettes.lerp(other.feedPalettes, t),
      options: options.lerp(other.options, t),
    );
  }
}
