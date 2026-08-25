import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// 250 ms fade + slight scale for all routes.
class _FadeScaleTransitionBuilder extends PageTransitionsBuilder {
  const _FadeScaleTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

const _transitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: _FadeScaleTransitionBuilder(),
    TargetPlatform.iOS: _FadeScaleTransitionBuilder(),
    TargetPlatform.macOS: _FadeScaleTransitionBuilder(),
    TargetPlatform.windows: _FadeScaleTransitionBuilder(),
    TargetPlatform.linux: _FadeScaleTransitionBuilder(),
    TargetPlatform.fuchsia: _FadeScaleTransitionBuilder(),
  },
);

TextTheme _baseTextTheme(Color ink, Color muted) {
  final headings = GoogleFonts.playfairDisplayTextTheme();
  final body = GoogleFonts.interTextTheme();
  // Display/headline sizes are pulled in slightly and given tighter tracking —
  // the airy default letterSpacing on a serif at 30 px+ reads dated.
  return TextTheme(
    displayLarge: headings.displayLarge?.copyWith(color: ink, letterSpacing: -0.5, fontWeight: FontWeight.w600, height: 1.1),
    displayMedium: headings.displayMedium?.copyWith(color: ink, letterSpacing: -0.4, fontWeight: FontWeight.w600, height: 1.12),
    headlineLarge: headings.headlineLarge?.copyWith(color: ink, letterSpacing: -0.3, fontWeight: FontWeight.w600, height: 1.15),
    headlineMedium: headings.headlineMedium?.copyWith(color: ink, letterSpacing: -0.2, fontWeight: FontWeight.w600, height: 1.2),
    headlineSmall: headings.headlineSmall?.copyWith(color: ink, letterSpacing: -0.1, fontWeight: FontWeight.w600, height: 1.25),
    titleLarge: headings.titleLarge?.copyWith(color: ink, letterSpacing: 0, fontWeight: FontWeight.w600),
    titleMedium: body.titleMedium?.copyWith(color: ink, fontWeight: FontWeight.w600, letterSpacing: -0.1),
    titleSmall: body.titleSmall?.copyWith(color: muted, fontWeight: FontWeight.w600),
    bodyLarge: body.bodyLarge?.copyWith(color: ink, height: 1.55, letterSpacing: -0.1),
    bodyMedium: body.bodyMedium?.copyWith(color: ink, height: 1.5, letterSpacing: -0.05),
    bodySmall: body.bodySmall?.copyWith(color: muted, height: 1.45),
    labelLarge: body.labelLarge?.copyWith(color: ink, letterSpacing: 0.2, fontWeight: FontWeight.w600),
    labelMedium: body.labelMedium?.copyWith(color: muted, letterSpacing: 0.4, fontWeight: FontWeight.w500),
    labelSmall: body.labelSmall?.copyWith(color: muted, letterSpacing: 1.2, fontWeight: FontWeight.w600),
  );
}

ThemeData _build({required bool dark}) {
  final ink = dark ? AppColors.cream : AppColors.charcoal;
  final muted = dark ? AppColors.mutedCream : AppColors.mutedCharcoal;
  final bg = dark ? AppColors.darkBg : AppColors.ivory;
  final surface = dark ? AppColors.darkSurface : AppColors.pureWhite;
  final hairline = dark ? AppColors.darkHairline : AppColors.champagne;

  final scheme = dark
      ? ColorScheme.dark(
          primary: AppColors.lightGold,
          onPrimary: AppColors.darkBg,
          secondary: AppColors.antiqueGold,
          onSecondary: AppColors.darkBg,
          surface: surface,
          onSurface: ink,
          error: AppColors.softRed,
        )
      : ColorScheme.light(
          primary: AppColors.deepGold,
          onPrimary: AppColors.ivory,
          secondary: AppColors.antiqueGold,
          onSecondary: AppColors.ivory,
          surface: surface,
          onSurface: ink,
          error: AppColors.softRed,
        );

  final inset = dark ? const Color(0xFF201C18) : const Color(0xFFF3EEE5);
  final gold = dark ? AppColors.lightGold : AppColors.deepGold;

  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: bg,
    colorScheme: scheme,
    textTheme: _baseTextTheme(ink, muted),
    iconTheme: IconThemeData(color: gold),
    dividerColor: hairline,
    pageTransitionsTheme: _transitions,
    // Softer, less "material" ripple across every tappable surface.
    splashFactory: InkSparkle.splashFactory,
    // Chrome is black in both themes — gold on black is the app's signature.
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.onyx,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ivory,
      elevation: 0,
      // Without this the M3 app bar tints itself as content scrolls under it,
      // which fights the warm page wash.
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.playfairDisplay(
        color: AppColors.ivory,
        fontSize: 21,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      iconTheme: const IconThemeData(color: AppColors.lightGold, size: 22),
      actionsIconTheme:
          const IconThemeData(color: AppColors.lightGold, size: 22),
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: hairline.withValues(alpha: 0.6), width: 1),
      ),
    ),
    // Inputs sit in a tinted well with no resting outline — the border only
    // appears (in gold) on focus.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inset,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: GoogleFonts.inter(color: muted, fontSize: 14),
      floatingLabelStyle: GoogleFonts.inter(
        color: gold,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: GoogleFonts.inter(color: muted, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: hairline.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.antiqueGold, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.softRed),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: hairline.withValues(alpha: 0.7)),
      ),
      titleTextStyle: GoogleFonts.playfairDisplay(
        color: ink,
        fontSize: 19,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: GoogleFonts.inter(color: muted, fontSize: 13.5, height: 1.5),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? AppColors.darkSurfaceAlt : AppColors.charcoal,
      contentTextStyle: GoogleFonts.inter(
        color: dark ? AppColors.cream : AppColors.ivory,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkSurfaceAlt : AppColors.charcoal,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      textStyle: GoogleFonts.inter(
        color: dark ? AppColors.cream : AppColors.ivory,
        fontSize: 11.5,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: inset,
      selectedColor: AppColors.champagne.withValues(alpha: dark ? 0.22 : 0.55),
      side: BorderSide(color: hairline.withValues(alpha: 0.7)),
      labelStyle: GoogleFonts.inter(
        color: ink,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: gold,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
      ),
    ),
    dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.antiqueGold,
      linearTrackColor: Color(0x33C9A961),
      circularTrackColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.ivory : muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? AppColors.antiqueGold
          : inset),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.transparent : hairline),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.antiqueGold,
      inactiveTrackColor: hairline,
      thumbColor: gold,
      overlayColor: AppColors.antiqueGold.withValues(alpha: 0.15),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: gold,
      textColor: ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
  );
}

ThemeData buildAppTheme() => _build(dark: false);
ThemeData buildDarkAppTheme() => _build(dark: true);
