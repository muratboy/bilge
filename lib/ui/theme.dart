import 'package:flutter/material.dart';

/// Uygulamanın renkleri. Açık ve koyu olmak üzere iki takım vardır; `context.p` ile okunur.
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.dark,
    required this.bg, required this.surface, required this.surface2,
    required this.ink, required this.ink2, required this.ink3, required this.line, required this.line2,
    required this.primary, required this.primaryD, required this.primarySoft, required this.primaryInk,
    required this.good, required this.goodD, required this.goodSoft, required this.goodInk,
    required this.bad, required this.badD, required this.badSoft, required this.badInk,
    required this.goldSoft, required this.goldInk, required this.blueInk,
  });

  final bool dark;
  final Color bg, surface, surface2, ink, ink2, ink3, line, line2;
  final Color primary, primaryD, primarySoft, primaryInk;
  final Color good, goodD, goodSoft, goodInk;
  final Color bad, badD, badSoft, badInk;
  final Color goldSoft, goldInk, blueInk;

  static const gold = Color(0xFFFFB800), goldD = Color(0xFFD99A00), fire = Color(0xFFFF8A1F), blue = Color(0xFF3A8DFF);

  /// Ünitelerin sırayla aldığı renkler; üstlerine beyaz yazı gelir.
  static const unitColors = [Color(0xFF7C5CFF), Color(0xFF0E9F92), Color(0xFFF2553F), Color(0xFF2F7FF0), Color(0xFFE4458F), Color(0xFFD98600), Color(0xFF2A9E4C)];
  static Color unitColor(int i) => unitColors[i % unitColors.length];
  static Color darken(Color c, [double amount = 0.3]) => Color.lerp(c, Colors.black, amount)!;

  static const light = Palette(
    dark: false,
    bg: Color(0xFFF7F4FB), surface: Color(0xFFFFFFFF), surface2: Color(0xFFF0ECF8),
    ink: Color(0xFF2A2342), ink2: Color(0xFF645D82), ink3: Color(0xFFA39DBD), line: Color(0xFFE7E1F2), line2: Color(0xFFD6CEEA),
    primary: Color(0xFF7C5CFF), primaryD: Color(0xFF5B3EDB), primarySoft: Color(0xFFEFEAFF), primaryInk: Color(0xFF5234D6),
    good: Color(0xFF22B573), goodD: Color(0xFF178A56), goodSoft: Color(0xFFDDF8EA), goodInk: Color(0xFF0F6A41),
    bad: Color(0xFFFF5263), badD: Color(0xFFD93548), badSoft: Color(0xFFFFE5E8), badInk: Color(0xFFB3202F),
    goldSoft: Color(0xFFFFF3CC), goldInk: Color(0xFF8F6400), blueInk: Color(0xFF1C5FC4),
  );

  static const night = Palette(
    dark: true,
    bg: Color(0xFF15121F), surface: Color(0xFF1F1B2E), surface2: Color(0xFF2A2540),
    ink: Color(0xFFF3F0FF), ink2: Color(0xFFB3ACCF), ink3: Color(0xFF7B749A), line: Color(0xFF322C48), line2: Color(0xFF463E64),
    primary: Color(0xFF9179FF), primaryD: Color(0xFF6A50E0), primarySoft: Color(0xFF2C2552), primaryInk: Color(0xFFC3B6FF),
    good: Color(0xFF2CC983), goodD: Color(0xFF1C9A62), goodSoft: Color(0xFF15382A), goodInk: Color(0xFF8AF0C0),
    bad: Color(0xFFFF6474), badD: Color(0xFFD43F50), badSoft: Color(0xFF451C24), badInk: Color(0xFFFFA3AD),
    goldSoft: Color(0xFF3A3010), goldInk: Color(0xFFFFD15C), blueInk: Color(0xFF8DBCFF),
  );

  @override
  Palette copyWith() => this;
  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) => t < 0.5 || other is! Palette ? this : other;
}

extension PaletteContext on BuildContext {
  Palette get p => Theme.of(this).extension<Palette>()!;
}

/// Nunito ile metin biçimi. Varsayılan ağırlık 700; başlıklar 900 kullanır.
TextStyle ts(double size, {FontWeight w = FontWeight.w700, Color? color, double height = 1.35, double spacing = 0}) =>
    TextStyle(fontFamily: 'Nunito', fontSize: size, fontWeight: w, color: color, height: height, letterSpacing: spacing);

ThemeData buildTheme(Palette p) => ThemeData(
      useMaterial3: true,
      brightness: p.dark ? Brightness.dark : Brightness.light,
      fontFamily: 'Nunito',
      scaffoldBackgroundColor: p.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: p.primary, brightness: p.dark ? Brightness.dark : Brightness.light).copyWith(surface: p.surface, primary: p.primary),
      extensions: [p],
      textTheme: TextTheme(bodyMedium: ts(16, color: p.ink), bodyLarge: ts(16, color: p.ink)),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        contentTextStyle: ts(15, w: FontWeight.w800, color: p.bg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
    );
