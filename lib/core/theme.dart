import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// Brand palette sampled from the Al's Pizza logo.
abstract final class AlsColors {
  static const cream = Color(0xFFFCF7EC); // logo background
  static const creamDeep = Color(0xFFF5EBD6);
  static const paper = Color(0xFFFFFDF8);
  static const brown = Color(0xFF5A210F); // "Als" script
  static const brownSoft = Color(0xFF7A4A33);
  static const ink = Color(0xFF2E140A);
  static const muted = Color(0xFF8C7462);
  static const line = Color(0xFFEADCC4);
  static const orange = Color(0xFFE8962A); // "PIZZA" lettering
  static const orangeLight = Color(0xFFF6B54E);
  static const orangeDeep = Color(0xFFD9771B);
  static const red = Color(0xFFB02013); // pepperoni
  static const basil = Color(0xFF356726);
  static const cheese = Color(0xFFF7C548);
  static const crust = Color(0xFFD8752A);
  static const success = Color(0xFF2F7A32);

  // Owner dashboard data colors — validated with the dataviz palette checker on white
  // (adjacent CVD ΔE in the 6–8 band, so stacked bars always ship gaps + direct labels).
  static const series1 = Color(0xFFD9771B);
  static const series2 = Color(0xFF8A3B1F);
  static const series3 = Color(0xFF3E7D32);
  static const grid = Color(0xFFEDE5D6);
  static const axis = Color(0xFF8C7F72);
  static const deltaGood = Color(0xFF006300);
  static const deltaBad = Color(0xFFD03B3B);
}

abstract final class AlsText {
  static TextStyle display(double size, {Color color = AlsColors.brown, FontWeight weight = FontWeight.w700, double? height}) =>
      GoogleFonts.fredoka(fontSize: size, fontWeight: weight, color: color, height: height ?? 1.1);

  static TextStyle body(double size, {Color color = AlsColors.ink, FontWeight weight = FontWeight.w600, double? height}) =>
      GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color, height: height ?? 1.35);

  static TextStyle label(double size, {Color color = AlsColors.muted}) =>
      GoogleFonts.nunito(fontSize: size, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.6);
}

ThemeData buildAlsTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AlsColors.orange,
    primary: AlsColors.brown,
    onPrimary: AlsColors.cream,
    secondary: AlsColors.orange,
    onSecondary: AlsColors.brown,
    error: AlsColors.red,
    surface: AlsColors.cream,
    onSurface: AlsColors.ink,
  );
  final text = GoogleFonts.nunitoTextTheme().apply(bodyColor: AlsColors.ink, displayColor: AlsColors.brown);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AlsColors.cream,
    textTheme: text.copyWith(
      headlineLarge: AlsText.display(32),
      headlineMedium: AlsText.display(26),
      headlineSmall: AlsText.display(22),
      titleLarge: AlsText.display(20, weight: FontWeight.w600),
      titleMedium: AlsText.body(16, weight: FontWeight.w800),
    ),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: AlsColors.cream,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AlsColors.brown,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: AlsText.display(20, weight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: AlsText.body(15, color: AlsColors.muted, weight: FontWeight.w500),
      labelStyle: AlsText.body(15, color: AlsColors.muted, weight: FontWeight.w600),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AlsColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AlsColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AlsColors.orange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AlsColors.red),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AlsColors.brown,
      contentTextStyle: AlsText.body(14, color: AlsColors.cream),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AlsColors.cream, surfaceTintColor: Colors.transparent),
    dividerTheme: const DividerThemeData(color: AlsColors.line, thickness: 1, space: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AlsColors.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AlsColors.basil : AlsColors.line),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}

/// Warm, soft elevation used for cards across both apps.
const alsShadow = [
  BoxShadow(color: Color(0x1A5A210F), blurRadius: 18, offset: Offset(0, 8)),
  BoxShadow(color: Color(0x0D5A210F), blurRadius: 4, offset: Offset(0, 1)),
];

/// Edge-to-edge system bars: transparent, dark icons, and no contrast scrim
/// (Android otherwise paints a dark scrim behind 3-button navigation).
const alsSystemBars = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
);
