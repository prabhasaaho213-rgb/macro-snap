import 'package:flutter/material.dart';

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.system,
);

/// Global name notifier — Settings writes to it, Home reads from it.
/// Eliminates the race between SharedPreferences reads and routeObserver
/// didPopNext callbacks.
final ValueNotifier<String> userNameNotifier = ValueNotifier('');

/// MacroSnap theme — matched to POP (com.popclub.android) UPI app:
/// near-black surfaces, a deep violet "curtain" hero gradient, and a single
/// saturated burnt-orange accent used for coins/rewards/CTAs. Public API
/// (color/method names) is unchanged so existing screens keep compiling;
/// only the underlying values moved off the old neon-rainbow palette.
class MacroSnapTheme {
  // ─── POP Palette ───────────────────────────────────────────
  /// Primary accent — POPcoin orange. Used for CTAs, streaks, highlight
  /// numbers, badges. This is the ONE saturated color that should recur
  /// everywhere, the way POP uses its coin-orange.
  static const Color neonGreen = Color(0xFFFF6B2B); // kept name for API compat
  /// Deep violet — hero/card gradient family (POP's "curtain" background).
  static const Color neonPink = Color(0xFFB0281F); // kept name; now "danger/rose"
  static const Color neonPurple = Color(0xFF8B3FE8);
  static const Color neonOrange = Color(0xFFFF6B2B);
  static const Color neonCyan = Color(0xFF9B7BFF); // lighter violet, kept name
  static const Color neonYellow = Color(0xFFF4A340); // amber, kept name
  static const Color neonRed = Color(0xFFE8481C);

  /// Semantic "done / success" green. [neonGreen] is the orange brand accent
  /// (the name is kept for API compatibility), so completed states must use
  /// this instead or they read as "active" rather than "done".
  static const Color successGreen = Color(0xFF2FA45F);

  /// The ONE brand CTA gradient — burnt-orange into a lighter orange.
  /// Every button / icon circle / highlight that still used the leftover
  /// orange→neon-green pair (0xFF00CC52, from the pre-redesign palette)
  /// must use this instead, so gradients never mix the old green in.
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B2B), Color(0xFFFFA45E)],
  );

  // ─── Semantic Macro Color Aliases ──────────────────────────
  /// Calories → coin orange (the brand accent)
  static const Color macroCalories = neonOrange;

  /// Protein → warm rose/red
  static const Color macroProtein = neonRed;

  /// Carbs → amber
  static const Color macroCarbs = neonYellow;

  /// Fats → violet
  static const Color macroFats = neonPurple;

  /// Fiber → green (kept distinct from the violet/orange brand pair so
  /// nutrient rings stay readable against each other)
  static const Color macroFiber = Color(0xFF3EA55A);

  // ─── General Purpose Semantic Tokens ───────────────────────
  // Dark-mode hierarchy: textPrimaryMuted (white70) is the BRIGHTEST token
  // (body text on dark gradient cards), then textSecondary (0.64, metadata),
  // then textTertiary (0.52, hints). Not a strict "primary > secondary"
  // ordering by name — brightness follows usage context. Keep it this way.
  /// Primary text color, slightly muted (body text, descriptions)
  static Color textPrimaryMuted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white70
      : const Color(0xFF475569);

  /// Secondary text color (subtle, for metadata/descriptions)
  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.64)
      : const Color(0xFF64748B);

  /// Tertiary text color (very subtle, for hints/placeholders)
  static Color textTertiary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.52)
      : const Color(0xFF94A3B8);

  /// Quaternary text color (barely visible, decorative)
  static Color textQuaternary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white38
      : const Color(0xFFCBD5E1);

  /// Green used for TEXT (not fills/icons). Always GREEN in both themes:
  /// after the orange redesign [neonGreen] became the orange accent, so
  /// following it here made the same text flip orange (dark) ↔ green
  /// (light). Instead keep the hue stable and only adjust the shade —
  /// deep green on light cards, a brighter green on near-black cards.
  static Color greenText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF3DDC84)
      : const Color(0xFF008A43);

  /// Subtle border color
  static Color borderSubtle(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white10
      : const Color(0xFFE2E8F0);

  // ─── Background & Surface Colors ───────────────────────────
  static const Color surfaceDark = Color(0xFF0A0A0A);
  static const Color surfaceLight = Color(0xFFF3EEFF);
  static const Color cardDark = Color(0xFF141414);
  static const Color cardDarkBorder = Color(0xFF2A2A2A);
  static const Color cardDarkLight = Color(0xFF1C1C1C);

  // ─── Card Decorations ──────────────────────────────────────
  /// Hero gradient card with neon border (Pop UPI hero card style).
  ///
  /// Theme-aware: dark mode keeps the signature near-black hero gradient;
  /// light mode uses the matching light gradient (same as [habitlyCard]) so
  /// hero cards like "Calorie goal" and "Make it count" never stay dark when
  /// the app is in light theme.
  static BoxDecoration habitlyHeroCard(
    BuildContext context, {
    BorderRadius? borderRadius = const BorderRadius.all(Radius.circular(28)),
    bool showBorder = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      // POP's signature hero look: a vertical violet "curtain" gradient
      // fading to near-black at the edges, not a diagonal neon blend.
      return BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF6D28D9),
            Color(0xFF3B0F82),
            Color(0xFF160A2E),
            Color(0xFF0A0A0A),
          ],
          stops: [0.0, 0.35, 0.7, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: borderRadius,
        border: showBorder ? Border.all(color: const Color(0xFF3D2166)) : null,
      );
    }
    return BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFF1E8FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: borderRadius,
      border: showBorder ? Border.all(color: const Color(0xFFCBB8F5)) : null,
    );
  }

  /// Standard elevated card (POP style — flat black, subtle border, no glow).
  ///
  /// Shares the exact same rich gradient background as the hero "Make it
  /// count" card in dark mode so every card across the app looks uniform.
  /// Light mode uses a matching light gradient to preserve readability.
  static BoxDecoration habitlyCard(
    BuildContext context, {
    BorderRadius? borderRadius = const BorderRadius.all(Radius.circular(28)),
    bool showBorder = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      // POP keeps the violet gradient reserved for hero banners only —
      // ordinary cards/rows are flat black with a hairline border.
      return BoxDecoration(
        color: cardDark,
        borderRadius: borderRadius,
        border: showBorder ? Border.all(color: cardDarkBorder) : null,
      );
    }
    return BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFF1E8FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: borderRadius,
      border: showBorder ? Border.all(color: const Color(0xFFCBB8F5)) : null,
    );
  }

  /// Mission-style emoji icon container — a flat tile tinted with the
  /// caller's accent, so each icon reads as its own colored chip instead of
  /// disappearing into the card behind it.
  ///
  /// Deliberately still FLAT: no gradient and no boxShadow/blur. The old glow
  /// smeared while cards were swiped (hence the RepaintBoundary around this
  /// tile in habits_tab.dart) and glyph shadows painted a ghost reflection
  /// under the emoji. Contrast comes from the accent tint and an accent-tinted
  /// hairline border — never from a shadow.
  static BoxDecoration emojiContainer(Color color) {
    // The tile used to ignore `color` entirely and paint cardDarkLight
    // (#1C1C1C) on a cardDark (#141414) card — an 8-step RGB difference, so
    // neither the tile nor the habit's own accent was visible. Blend the
    // accent over a slightly lifted base instead: the white lift separates
    // the tile from the card, the accent supplies the hue.
    final base = Color.alphaBlend(
      Colors.white.withValues(alpha: 0.06),
      cardDarkLight,
    );
    return BoxDecoration(
      color: Color.alphaBlend(color.withValues(alpha: 0.20), base),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: Color.alphaBlend(color.withValues(alpha: 0.55), cardDarkBorder),
        width: 1,
      ),
    );
  }

  /// Style for emoji glyphs — FLAT, with no text shadows.
  ///
  /// Shadows on emoji glyphs previously painted a dark "ghost reflection"
  /// under the emoji (visible when swiping cards or on tinted chips). Every
  /// emoji surface in the app now renders flat; the accent-tinted tile behind
  /// it ([emojiContainer]) provides the depth instead.
  static TextStyle emojiStyle({double fontSize = 25}) {
    return TextStyle(fontSize: fontSize);
  }

  /// Accent pill — POP uses solid-fill badges (e.g. the orange "New" tag),
  /// not low-alpha tinted outlines.
  /// Pill background for accent-coloured badges (scans remaining, meal
  /// streak, kcal totals, "latest release" chip).
  ///
  /// This used to fill the pill with [color] while every call site painted its
  /// icon and label in that same colour — so with the POP orange accent the
  /// header scans badge, the streak pill and the kcal pill all rendered as
  /// empty orange blobs (orange-on-orange). The pill is now a low-alpha tint
  /// of [color] with a matching hairline, so accent-coloured content stays
  /// legible on top in both light and dark themes.
  static BoxDecoration neonPill(Color color) {
    return BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    );
  }

  // ─── Input Theme ───────────────────────────────────────────
  static InputDecorationTheme _inputTheme(bool dark) {
    final bg = dark ? cardDark : Colors.white;
    final border = dark ? Colors.white10 : const Color(0xFFE8DEFF);
    return InputDecorationTheme(
      filled: true,
      fillColor: bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: neonGreen, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: neonPink, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: neonPink, width: 2),
      ),
      labelStyle: TextStyle(
        fontSize: 14,
        color: dark
            ? Colors.white.withValues(alpha: 0.64)
            : const Color(0xFF94A3B8),
      ),
      hintStyle: TextStyle(
        fontSize: 14,
        color: dark
            ? Colors.white.withValues(alpha: 0.4)
            : const Color(0xFFCBD5E1),
      ),
    );
  }

  // ─── Light Theme ───────────────────────────────────────────
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: neonGreen,
        secondary: neonPink,
        tertiary: neonCyan,
        surface: surfaceLight,
        error: neonPink,
      ),
      scaffoldBackgroundColor: surfaceLight,
      inputDecorationTheme: _inputTheme(false),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: neonGreen,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: neonGreen,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      // Inter is bundled as an asset (assets/fonts/Inter.ttf) — referenced
      // directly so there is no runtime font fetch. The variable font covers
      // every weight the theme uses.
      textTheme: ThemeData.light().textTheme
          .apply(fontFamily: 'Inter')
          .copyWith(
            displayLarge: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              fontFamily: 'Inter',
            ),
            displayMedium: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              fontFamily: 'Inter',
            ),
            headlineLarge: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              fontFamily: 'Inter',
            ),
            headlineMedium: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFamily: 'Inter',
            ),
            titleLarge: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
            ),
            titleMedium: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
            ),
            bodyLarge: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              fontFamily: 'Inter',
            ),
            bodyMedium: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'Inter',
            ),
            labelLarge: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
            ),
          ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFF1A1A1A),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A1A1A),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        shadowColor: neonGreen.withValues(alpha: 0.08),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        elevation: 0,
        selectedItemColor: neonGreen,
        unselectedItemColor: Color(0xFF94A3B8),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
      ),
    );
  }

  // ─── Dark Theme (Habitly Noir) ─────────────────────────────
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: neonOrange,
        secondary: neonPurple,
        tertiary: neonCyan,
        surface: surfaceDark,
        error: neonRed,
      ),
      scaffoldBackgroundColor: surfaceDark,
      inputDecorationTheme: _inputTheme(true),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: neonOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: neonOrange,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textTheme: ThemeData.dark().textTheme
          .apply(fontFamily: 'Inter')
          .copyWith(
            // Headlines are upright. These used to be Inter italic (a "POP
            // editorial" experiment), but on the login/splash headlines the
            // slant read as a rendering glitch — "Welcome to MacroSnap"
            // looked tilted. Keep the size/weight, drop the slant.
            displayLarge: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Colors.white,
              fontFamily: 'Inter',
            ),
            displayMedium: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Colors.white,
              fontFamily: 'Inter',
            ),
            headlineLarge: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFamily: 'Inter',
            ),
            headlineMedium: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFamily: 'Inter',
            ),
            titleLarge: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontFamily: 'Inter',
            ),
            titleMedium: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontFamily: 'Inter',
            ),
            bodyLarge: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
              fontFamily: 'Inter',
            ),
            bodyMedium: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
              fontFamily: 'Inter',
            ),
            labelLarge: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontFamily: 'Inter',
            ),
          ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        elevation: 0,
        // POP's active tab is white (not brand-orange) — orange is reserved
        // for the coin/CTA accent, not nav state.
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white30,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Color(0xFF121212),
      ),
    );
  }

  // ─── Glass Decoration (unified) ────────────────────────────
  static BoxDecoration glassDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? habitlyCard(context)
        : BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFF4EFFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFC8BEFF)),
            boxShadow: [
              BoxShadow(
                color: neonGreen.withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 8),
              ),
            ],
          );
  }

}
