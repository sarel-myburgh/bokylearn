// ─────────────────────────────────────────────────────────────────────────────
// main.dart — App entry point
//
// Responsibilities:
//   1. Initialise Hive (local database) before the widget tree is built.
//   2. Wrap the whole app in a Riverpod ProviderScope so every widget in the
//      tree can access providers (settings, feed state, etc.).
//   3. Configure global theme and hand routing off to AppRouter.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/constants.dart';
import 'core/router.dart';
import 'data/local/facts_db.dart';

void main() async {
  // Ensure Flutter's native binding is ready before calling any platform
  // channel code (Hive needs the file system, which requires this).
  WidgetsFlutterBinding.ensureInitialized();

  // Open all Hive boxes (facts, seen facts, reactions, bookmarks, etc.).
  // This must complete before the UI renders so the feed can query instantly.
  await FactsDb.init();

  // ProviderScope is the root of all Riverpod state. Everything beneath it
  // can watch / read providers. The app itself is stateless — all state lives
  // in providers.
  runApp(const ProviderScope(child: BokyLearnApp()));
}

class BokyLearnApp extends StatelessWidget {
  const BokyLearnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BokyLearn',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.router,
    );
  }

  // Builds a vivid, Nintendo-inspired Material 3 theme.
  //
  // Rather than using ColorScheme.fromSeed (which intentionally generates
  // de-saturated tonal palettes), we start from the seed as a base and then
  // forcibly replace the key role colours with the full-saturation versions
  // from BokyPalette. The result keeps M3's surface/outline/error logic while
  // making primaries, secondaries, and containers visually punchy.
  ThemeData _buildTheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    // fromSeed gives us the correct surface, outline, and error tones.
    // We then override the brand colours to be fully saturated.
    final base = ColorScheme.fromSeed(
      seedColor: BokyPalette.blue,
      brightness: brightness,
    );

    final scheme = base.copyWith(
      // Primary — vivid cobalt blue in light, softer sky blue in dark
      // (M3 convention: on-dark surfaces, brand colours are lightened so
      // text/icons placed on them remain readable).
      primary:            isLight ? BokyPalette.blue   : const Color(0xFF90CAF9),
      onPrimary:          Colors.white,
      primaryContainer:   isLight ? const Color(0xFFBBDEFB) : const Color(0xFF0D47A1),
      onPrimaryContainer: isLight ? const Color(0xFF0D47A1) : const Color(0xFFBBDEFB),

      // Secondary — vivid deep orange, warm and energetic.
      secondary:            isLight ? BokyPalette.orange : const Color(0xFFFFAB91),
      onSecondary:          Colors.white,
      secondaryContainer:   isLight ? const Color(0xFFFFCCBC) : const Color(0xFFBF360C),
      onSecondaryContainer: isLight ? const Color(0xFFBF360C) : const Color(0xFFFFCCBC),

      // Tertiary — vivid forest green.
      tertiary:            isLight ? BokyPalette.green  : const Color(0xFFA5D6A7),
      onTertiary:          Colors.white,
      tertiaryContainer:   isLight ? const Color(0xFFC8E6C9) : const Color(0xFF1B5E20),
      onTertiaryContainer: isLight ? const Color(0xFF1B5E20) : const Color(0xFFC8E6C9),
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,

      // ── App bar ────────────────────────────────────────────────────────────
      // Solid vivid-blue bar with white elements — bold, immediately readable,
      // and distinct from the white content surface below.
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFA59132),
        foregroundColor: Color(0xFFFFFBDB),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: Color(0xFFFFFBDB)),
        titleTextStyle: TextStyle(
          color: Color(0xFFFFFBDB),
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          fontFamily: 'Nunito',
        ),
      ),

      // ── Cards ──────────────────────────────────────────────────────────────
      // Larger radius for a friendlier, rounder feel. Clip so the coloured
      // left strip (added per-card) is properly bounded.
      cardTheme: CardThemeData(
        elevation: isLight ? 3 : 4,
        shadowColor: Colors.black45,
        color: isLight ? BokyPalette.cardBackground : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
      ),

      // ── Buttons — pill-shaped throughout ──────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      // ── Input fields ───────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),

      // ── Chips (follow-up question chips) ───────────────────────────────────
      chipTheme: const ChipThemeData(shape: StadiumBorder()),

      // ── Typography — Nunito throughout, bolder weights ────────────────────
      textTheme: GoogleFonts.nunitoTextTheme(
        const TextTheme(
          titleLarge:  TextStyle(fontWeight: FontWeight.w800),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
          titleSmall:  TextStyle(fontWeight: FontWeight.w700),
          labelLarge:  TextStyle(fontWeight: FontWeight.w700),
          labelMedium: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
