import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // — Gold (theme-independent) —
  static const Color antiqueGold = Color(0xFFC9A961);
  static const Color deepGold = Color(0xFFA8873E);
  static const Color lightGold = Color(0xFFD4B976);
  static const Color champagne = Color(0xFFE8D9B0);
  static const Color softRed = Color(0xFFC97561);
  static const Color softGreen = Color(0xFF8FAE6F);

  // — Light theme —
  static const Color ivory = Color(0xFFFAF7F2);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color charcoal = Color(0xFF2C2825);
  static const Color mutedCharcoal = Color(0xFF6B6560);

  // — Dark theme (sumi ink) —
  // Pushed close to true black so gold reads as the single bright element.
  static const Color darkBg = Color(0xFF0B0A08);
  static const Color darkSurface = Color(0xFF15120F);
  static const Color darkSurfaceAlt = Color(0xFF1E1A15);
  static const Color cream = Color(0xFFEDE6D6);
  static const Color mutedCream = Color(0xFF9C9486);
  static const Color darkHairline = Color(0xFF352C22);

  // — Black chrome —
  // The app bar and nav bar are black in BOTH themes: gold on black is the
  // app's signature, and keeping the chrome constant makes light/dark feel
  // like one product rather than two skins.
  static const Color onyx = Color(0xFF141210);
  static const Color onyxLift = Color(0xFF211D18);
  static const Color onyxEdge = Color(0xFF2E2820);

  static const LinearGradient chromeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B1815), Color(0xFF0E0C0A)],
  );

  // — 오방색 accents —
  // The five Korean cardinal colours, desaturated to sit beside gold without
  // fighting it. Used for status, part of speech and section accents so the
  // UI carries information in colour instead of in more text.
  static const Color jade = Color(0xFF4F8F7B); // 청 — verbs
  static const Color sky = Color(0xFF4A87A4); // 청 (light)
  static const Color indigo = Color(0xFF48619A); // 감청 — nouns
  static const Color plum = Color(0xFF8B4A6B); // 자주 — descriptive verbs
  static const Color clay = Color(0xFFB0794A); // 황토 — particles
  static const Color vermilion = Color(0xFFC2543F); // 적 — destructive

  /// Colour identifying a part of speech. Takes the raw code string so this
  /// file stays free of model imports.
  static Color forPartOfSpeech(String code) {
    switch (code) {
      case 'noun':
        return indigo;
      case 'verb':
        return jade;
      case 'descriptive_verb':
        return plum;
      case 'adverb':
        return sky;
      case 'particle':
        return clay;
      case 'expression':
        return deepGold;
      default:
        return antiqueGold;
    }
  }

  // — Constants —
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lightGold, deepGold],
  );

  // Soft warm shadow. Blur kept modest (12, not 24) — a wide Gaussian blur is
  // one of the more expensive things to rasterize, and the difference is
  // barely visible at this opacity.
  static const BoxShadow warmShadow = BoxShadow(
    color: Color(0x1AC9A961),
    blurRadius: 12,
    offset: Offset(0, 5),
  );

  // — Context-aware accessors —
  static bool _isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

  static Color background(BuildContext c) => _isDark(c) ? darkBg : ivory;
  static Color surface(BuildContext c) => _isDark(c) ? darkSurface : pureWhite;
  static Color subtleSurface(BuildContext c) => _isDark(c) ? darkSurfaceAlt : ivory;
  static Color ink(BuildContext c) => _isDark(c) ? cream : charcoal;
  static Color mutedInk(BuildContext c) => _isDark(c) ? mutedCream : mutedCharcoal;
  static Color hairline(BuildContext c) => _isDark(c) ? darkHairline : champagne;

  // ——— Modern surface & accent tokens ———
  //
  // Everything above is unchanged; what follows layers a small design system
  // on top of it so screens stop hand-rolling one-off colours and shadows.

  /// The tinted well an inset control sits in (search fields, segmented
  /// controls, chip rows). One step *back* from [surface].
  static Color inset(BuildContext c) =>
      _isDark(c) ? const Color(0xFF201C18) : const Color(0xFFF3EEE5);

  /// A card that should read as lifted above the page.
  static Color raised(BuildContext c) =>
      _isDark(c) ? darkSurfaceAlt : pureWhite;

  /// Faint gold wash used behind selected chips, badges and callouts.
  static Color goldTint(BuildContext c) => _isDark(c)
      ? antiqueGold.withValues(alpha: 0.14)
      : champagne.withValues(alpha: 0.38);

  /// Hairline strong enough to read as a divider on a tinted surface.
  static Color strongHairline(BuildContext c) => _isDark(c)
      ? const Color(0xFF4B4238)
      : const Color(0xFFE0D3B4);

  /// Page background wash — a barely-there warm gradient that keeps large
  /// empty areas from looking flat. Cheap: two stops, no blur.
  static LinearGradient pageGradient(BuildContext c) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: _isDark(c)
            ? const [Color(0xFF1E1A16), darkBg]
            : const [Color(0xFFFDFBF7), ivory],
      );

  /// Soft gold sheen for headers and selected surfaces.
  static const LinearGradient champagneGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF3E7C8), Color(0xFFE3D0A2)],
  );

  /// Resting elevation for cards. Deeper and cooler in the dark theme, where
  /// a gold-tinted shadow simply disappears.
  static List<BoxShadow> cardShadow(BuildContext c) => _isDark(c)
      ? const [
          BoxShadow(color: Color(0x40000000), blurRadius: 14, offset: Offset(0, 6)),
        ]
      : const [
          BoxShadow(color: Color(0x14C9A961), blurRadius: 16, offset: Offset(0, 6)),
          BoxShadow(color: Color(0x0A2C2825), blurRadius: 3, offset: Offset(0, 1)),
        ];

  /// Status colours. Both are gold: learning and reinforced are two stages of
  /// the same collection, not two different things, and giving them separate
  /// hues made the combined list read as two lists pushed together. The
  /// status pill and the cycle icon still name which stage a word is in.
  static const Color statusLearning = deepGold;
  static const Color statusReinforcement = deepGold;

  /// A tinted well in [c]'s hue — the standard treatment for coloured chips.
  static Color tintOf(BuildContext context, Color c) =>
      c.withValues(alpha: _isDark(context) ? 0.20 : 0.12);

  /// Readable version of an accent against the current background.
  static Color onSurfaceAccent(BuildContext context, Color c) =>
      _isDark(context) ? Color.lerp(c, cream, 0.34)! : Color.lerp(c, charcoal, 0.12)!;

  /// Elevation for floating chrome — the bottom bar and the add button.
  static List<BoxShadow> floatShadow(BuildContext c) => _isDark(c)
      ? const [
          BoxShadow(color: Color(0x59000000), blurRadius: 22, offset: Offset(0, 8)),
        ]
      : const [
          BoxShadow(color: Color(0x1FA8873E), blurRadius: 24, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x0F2C2825), blurRadius: 4, offset: Offset(0, 2)),
        ];
}

/// Corner radii, named by role rather than by number so the whole app can be
/// re-rounded from one place.
class AppRadius {
  AppRadius._();

  /// Chips, pills, small badges.
  static const double xs = 10;

  /// Inputs, inner blocks, list rows.
  static const double sm = 14;

  /// Standard card.
  static const double md = 18;

  /// Feature card, sheet header, hero surfaces.
  static const double lg = 24;

  /// Bottom sheets and the floating nav bar.
  static const double xl = 28;

  static BorderRadius all(double r) => BorderRadius.circular(r);
}
