import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens — cores, tipografia e formas do app.
/// Metáfora: água/fluidez. Verde-água como identidade, coral como
/// contraponto quente reservado só para cobrança/alerta.
class AppColors {
  AppColors._();

  // Primária
  static const Color verdeAguaProfundo = Color(0xFF0E6E64);
  static const Color verdeAguaProfundoDark = Color(0xFF0A544C); // hover/pressed

  // Accent
  static const Color mentaViva = Color(0xFF5EEAC0);

  // Contraponto quente — só cobrança/alerta/atraso
  static const Color coralAceso = Color(0xFFFF6B4A);

  // Texto
  static const Color tintaProfunda = Color(0xFF0B211E);

  // Fundo
  static const Color nevoaClara = Color(0xFFF3FAF8);

  // Bordas / neutros
  static const Color areiaNeutra = Color(0xFFE4E9E7);

  // Modo escuro
  static const Color tintaProfundaDarkBg = Color(0xFF0B211E);
  static const Color mentaVivaDark = Color(0xFF7BF2CE); // mais saturada p/ contraste
  static const Color nevoaClaraDarkText = Color(0xFFF3FAF8);
}

class AppTheme {
  AppTheme._();

  // Raio padrão dos cards — cantos generosos, parte da identidade.
  static const double cardRadius = 18;
  static const double buttonRadius = 100; // pill

  /// Fonte de destaque (títulos, valores em R$ grandes).
  /// Se "Cabinet Grotesk"/"General Sans" estiverem disponíveis como
  /// fonte custom em pubspec.yaml, troque GoogleFonts.spaceGrotesk
  /// por TextStyle(fontFamily: 'CabinetGrotesk', ...).
  static TextStyle _display(TextStyle base) =>
      GoogleFonts.spaceGrotesk(textStyle: base, fontWeight: FontWeight.w600);

  /// Fonte de corpo/texto.
  static TextStyle _body(TextStyle base) =>
      GoogleFonts.sora(textStyle: base);

  /// Fonte pra valores monetários — números tabulares, sensação de extrato.
  static TextStyle _money(TextStyle base) => GoogleFonts.ibmPlexMono(
        textStyle: base,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w600,
      );

  static TextTheme _textTheme(Brightness brightness) {
    final Color onSurface =
        brightness == Brightness.light ? AppColors.tintaProfunda : AppColors.nevoaClaraDarkText;

    return TextTheme(
      displayLarge: _display(TextStyle(fontSize: 40, height: 1.1, color: onSurface)),
      displayMedium: _display(TextStyle(fontSize: 32, height: 1.15, color: onSurface)),
      displaySmall: _display(TextStyle(fontSize: 26, height: 1.2, color: onSurface)),
      headlineMedium: _display(TextStyle(fontSize: 22, height: 1.25, color: onSurface)),
      titleLarge: _body(TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: onSurface)),
      titleMedium: _body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: onSurface)),
      bodyLarge: _body(TextStyle(fontSize: 16, color: onSurface)),
      bodyMedium: _body(TextStyle(fontSize: 14, color: onSurface)),
      bodySmall: _body(TextStyle(fontSize: 12, color: onSurface.withOpacity(0.7))),
      labelLarge: _body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface)),
    );
  }

  /// Estilo dedicado pra valores em R$ — usar explicitamente nos widgets
  /// de saldo/cobrança, não faz parte do TextTheme padrão do Material.
  static TextStyle moneyStyle({
    double fontSize = 28,
    Color color = AppColors.tintaProfunda,
  }) =>
      _money(TextStyle(fontSize: fontSize, color: color));

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.verdeAguaProfundo,
      brightness: Brightness.light,
      primary: AppColors.verdeAguaProfundo,
      secondary: AppColors.mentaViva,
      error: AppColors.coralAceso,
      surface: AppColors.nevoaClara,
      onPrimary: Colors.white,
      onSecondary: AppColors.tintaProfunda,
      onSurface: AppColors.tintaProfunda,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.nevoaClara,
      textTheme: _textTheme(Brightness.light),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.nevoaClara,
        foregroundColor: AppColors.tintaProfunda,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: _display(
          const TextStyle(fontSize: 20, color: AppColors.tintaProfunda),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: AppColors.areiaNeutra, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.verdeAguaProfundo,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: _body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      // Botão de destaque pra ação de cobrança ("Cobra Aí") — usa o coral.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.coralAceso,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: _body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.verdeAguaProfundo,
          side: const BorderSide(color: AppColors.verdeAguaProfundo, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.areiaNeutra),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.areiaNeutra),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.verdeAguaProfundo, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.verdeAguaProfundo,
        unselectedItemColor: Color(0xFF8FA39E),
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.areiaNeutra,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.verdeAguaProfundo,
      brightness: Brightness.dark,
      primary: AppColors.mentaVivaDark,
      secondary: AppColors.mentaVivaDark,
      error: AppColors.coralAceso,
      surface: const Color(0xFF122B27),
      onPrimary: AppColors.tintaProfunda,
      onSurface: AppColors.nevoaClaraDarkText,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.tintaProfundaDarkBg,
      textTheme: _textTheme(Brightness.dark),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.tintaProfundaDarkBg,
        foregroundColor: AppColors.nevoaClaraDarkText,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: _display(
          const TextStyle(fontSize: 20, color: AppColors.nevoaClaraDarkText),
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF122B27),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: Color(0xFF1D3D37), width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.mentaVivaDark,
          foregroundColor: AppColors.tintaProfunda,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: _body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.coralAceso,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
    );
  }
}

/// Uso no MaterialApp:
///
/// MaterialApp(
///   theme: AppTheme.light(),
///   darkTheme: AppTheme.dark(),
///   themeMode: ThemeMode.system,
///   ...
/// )
///
/// Dependências necessárias no pubspec.yaml:
///   google_fonts: ^6.2.1
