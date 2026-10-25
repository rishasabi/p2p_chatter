import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Chatter's look, "lantern relay": an indigo night (or a pale dawn) where
/// your phone and everything you send glows ember, and the mesh itself is
/// drawn as nodes, links and range rings.
///
/// Type: Unbounded, wide and rounded like a broadcast call sign, for the
/// wordmark, titles, headings and buttons; Figtree for everything people
/// read at length, messages first.
///
/// Widgets read colours from [ColorScheme] and [ChatterColors] and text
/// styles from [TextTheme]; nothing below the theme hardcodes either.
abstract final class AppTheme {
  static const displayFont = 'Unbounded';
  static const textFont = 'Figtree';

  /// Ember: you, your messages, your links, the brand mark.
  static const ember = Color(0xFFFFB547);
  static const onEmber = Color(0xFF241400);

  /// Night ink: the dark background and the launcher icon tile.
  static const night = Color(0xFF0E1020);

  static ThemeData light() => _build(_lightScheme, ChatterColors.light);
  static ThemeData dark() => _build(_darkScheme, ChatterColors.dark);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    // Ember is too light for text and controls on dawn surfaces, so
    // interactive colour uses its deep, readable shade
    primary: Color(0xFF8A4B00),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFDDB0),
    onPrimaryContainer: Color(0xFF2D1600),
    secondary: Color(0xFF55536E),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE3E0F0),
    onSecondaryContainer: Color(0xFF1B1A2E),
    tertiary: Color(0xFF136B46),
    onTertiary: Color(0xFFFFFFFF),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFCDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF4F2FA),
    onSurface: Color(0xFF1B1A2E),
    onSurfaceVariant: Color(0xFF555370),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFAF9FD),
    surfaceContainer: Color(0xFFFFFFFF),
    surfaceContainerHigh: Color(0xFFFFFFFF),
    surfaceContainerHighest: Color(0xFFE6E3F0),
    outline: Color(0xFF7A7893),
    outlineVariant: Color(0xFFDAD7E6),
    inverseSurface: Color(0xFF24263D),
    onInverseSurface: Color(0xFFECEBF7),
    inversePrimary: ember,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Colors.transparent,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: ember,
    onPrimary: onEmber,
    primaryContainer: Color(0xFF5C3600),
    onPrimaryContainer: Color(0xFFFFDDB0),
    secondary: Color(0xFFC0BEDB),
    onSecondary: Color(0xFF24263D),
    secondaryContainer: Color(0xFF2A2D47),
    onSecondaryContainer: Color(0xFFE3E0F0),
    tertiary: Color(0xFF74D1B0),
    onTertiary: Color(0xFF003827),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: night,
    onSurface: Color(0xFFECEBF7),
    onSurfaceVariant: Color(0xFFA6A4C2),
    surfaceContainerLowest: Color(0xFF0A0B17),
    surfaceContainerLow: Color(0xFF13152A),
    surfaceContainer: Color(0xFF171A2E),
    surfaceContainerHigh: Color(0xFF1D2037),
    surfaceContainerHighest: Color(0xFF262A44),
    outline: Color(0xFF706E8F),
    outlineVariant: Color(0xFF2A2D47),
    inverseSurface: Color(0xFFECEBF7),
    onInverseSurface: Color(0xFF1B1A2E),
    inversePrimary: Color(0xFF8A4B00),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Colors.transparent,
  );

  /// Unbounded is wide, so it runs a step smaller than a text face would and
  /// is tightened at large sizes; Figtree carries the reading sizes, with
  /// message text at 17px and a 1.4 line height for long threads.
  static TextTheme _textTheme(ColorScheme cs) {
    TextStyle display(double size, FontWeight weight, double height, double tracking) => TextStyle(
          fontFamily: displayFont,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: tracking,
        );
    TextStyle text(double size, FontWeight weight, double height, [double tracking = 0]) => TextStyle(
          fontFamily: textFont,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: tracking,
        );
    return TextTheme(
      displayLarge: display(44, FontWeight.w700, 1.05, -1.6),
      displayMedium: display(36, FontWeight.w700, 1.1, -1.2),
      displaySmall: display(30, FontWeight.w700, 1.1, -0.9),
      headlineLarge: display(28, FontWeight.w700, 1.15, -0.8),
      headlineMedium: display(25, FontWeight.w700, 1.15, -0.7),
      headlineSmall: display(22, FontWeight.w600, 1.2, -0.5),
      titleLarge: display(18, FontWeight.w600, 1.25, -0.3),
      titleMedium: text(17, FontWeight.w700, 1.3),
      titleSmall: display(13, FontWeight.w600, 1.3, 0),
      bodyLarge: text(17, FontWeight.w400, 1.4),
      bodyMedium: text(15, FontWeight.w400, 1.4),
      bodySmall: text(13, FontWeight.w500, 1.35, 0.1),
      labelLarge: display(14, FontWeight.w600, 1.2, -0.1),
      labelMedium: text(13, FontWeight.w700, 1.25, 0.1),
      labelSmall: text(12, FontWeight.w600, 1.25, 0.2),
    ).apply(bodyColor: cs.onSurface, displayColor: cs.onSurface);
  }

  static ThemeData _build(ColorScheme cs, ChatterColors chatter) {
    final text = _textTheme(cs);
    final isDark = cs.brightness == Brightness.dark;
    const controlShape = StadiumBorder();
    const buttonSize = Size(64, 48);
    final fieldFill = isDark ? cs.surfaceContainer : cs.surfaceContainerLowest;
    OutlineInputBorder fieldBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      brightness: cs.brightness,
      fontFamily: textFont,
      textTheme: text,
      scaffoldBackgroundColor: cs.surface,
      canvasColor: cs.surface,
      extensions: [chatter],
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        toolbarHeight: 64,
        titleTextStyle: text.headlineSmall,
        systemOverlayStyle: overlayStyle(cs.brightness),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        // The selected destination lights up ember, like your node on the map
        indicatorColor: ember,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => text.labelMedium!.copyWith(
              color: states.contains(WidgetState.selected) ? cs.onSurface : cs.onSurfaceVariant,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected) ? onEmber : cs.onSurfaceVariant,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: cs.surfaceContainer,
        indicatorColor: ember,
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: const IconThemeData(color: onEmber),
        unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant),
        selectedLabelTextStyle: text.labelMedium!.copyWith(color: cs.onSurface),
        unselectedLabelTextStyle: text.labelMedium!.copyWith(color: cs.onSurfaceVariant),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: cs.onSurface,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicator: UnderlineTabIndicator(
          borderSide: const BorderSide(color: ember, width: 3),
          borderRadius: BorderRadius.circular(2),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: cs.outlineVariant,
        labelStyle: text.labelMedium!.copyWith(fontSize: 14),
        unselectedLabelStyle: text.labelMedium!.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        hintStyle: text.bodyLarge!.copyWith(color: cs.onSurfaceVariant),
        labelStyle: text.bodyLarge!.copyWith(color: cs.onSurfaceVariant),
        floatingLabelStyle: text.labelMedium!.copyWith(color: cs.primary),
        helperStyle: text.bodySmall!.copyWith(color: cs.onSurfaceVariant),
        errorStyle: text.bodySmall!.copyWith(color: cs.error),
        prefixIconColor: cs.onSurfaceVariant,
        suffixIconColor: cs.onSurfaceVariant,
        border: fieldBorder(cs.outlineVariant),
        enabledBorder: fieldBorder(cs.outlineVariant),
        focusedBorder: fieldBorder(cs.primary, 2),
        errorBorder: fieldBorder(cs.error),
        focusedErrorBorder: fieldBorder(cs.error, 2),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: cs.primary,
        selectionColor: cs.primary.withValues(alpha: 0.32),
        selectionHandleColor: cs.primary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: controlShape,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 22),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: controlShape,
          textStyle: text.labelLarge,
          foregroundColor: cs.primary,
          side: BorderSide(color: cs.outline),
          padding: const EdgeInsets.symmetric(horizontal: 22),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: buttonSize, shape: controlShape, textStyle: text.labelLarge),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: buttonSize,
          textStyle: text.labelMedium!.copyWith(fontSize: 14),
          selectedBackgroundColor: ember,
          selectedForegroundColor: onEmber,
          side: BorderSide(color: cs.outline),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        minVerticalPadding: 12,
        iconColor: cs.onSurfaceVariant,
        titleTextStyle: text.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onEmber : cs.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? ember : cs.surfaceContainerHighest,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : cs.outline,
        ),
      ),
      dividerTheme: DividerThemeData(color: cs.outlineVariant, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: cs.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: cs.outlineVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.inverseSurface,
        contentTextStyle: text.bodyMedium!.copyWith(color: cs.onInverseSurface),
        actionTextColor: cs.inversePrimary,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        elevation: 2,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        textStyle: text.bodyLarge,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.primary, linearTrackColor: cs.outlineVariant),
      tooltipTheme: TooltipThemeData(
        textStyle: text.bodySmall!.copyWith(color: cs.onInverseSurface),
        decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(8)),
      ),
      badgeTheme: const BadgeThemeData(backgroundColor: ember, textColor: onEmber),
      iconTheme: IconThemeData(color: cs.onSurfaceVariant, size: 24),
    );
  }

  /// Status and navigation bar icons that stay visible on either theme.
  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final base = brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
    return base.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: brightness == Brightness.dark ? _darkScheme.surfaceContainer : Colors.white,
      systemNavigationBarIconBrightness: brightness == Brightness.dark ? Brightness.light : Brightness.dark,
    );
  }
}

/// Colours with a chat-specific meaning that [ColorScheme] has no role for.
@immutable
class ChatterColors extends ThemeExtension<ChatterColors> {
  final Color bubbleOut;
  final Color onBubbleOut;
  final Color bubbleIn;
  final Color onBubbleIn;

  /// A peer reachable right now: the ring round their node.
  final Color reach;

  /// Links on the mesh map, drawn out from your node.
  final Color link;

  /// Range rings and out-of-range nodes on the mesh map.
  final Color faint;

  const ChatterColors({
    required this.bubbleOut,
    required this.onBubbleOut,
    required this.bubbleIn,
    required this.onBubbleIn,
    required this.reach,
    required this.link,
    required this.faint,
  });

  static const light = ChatterColors(
    bubbleOut: AppTheme.ember,
    onBubbleOut: AppTheme.onEmber,
    bubbleIn: Color(0xFFFFFFFF),
    onBubbleIn: Color(0xFF1B1A2E),
    reach: Color(0xFF136B46),
    link: Color(0xFFC77700),
    faint: Color(0xFFCFCBE0),
  );

  static const dark = ChatterColors(
    bubbleOut: AppTheme.ember,
    onBubbleOut: AppTheme.onEmber,
    bubbleIn: Color(0xFF20243B),
    onBubbleIn: Color(0xFFECEBF7),
    reach: Color(0xFF74D1B0),
    link: AppTheme.ember,
    faint: Color(0xFF34385A),
  );

  static ChatterColors of(BuildContext context) =>
      Theme.of(context).extension<ChatterColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  ChatterColors copyWith({
    Color? bubbleOut,
    Color? onBubbleOut,
    Color? bubbleIn,
    Color? onBubbleIn,
    Color? reach,
    Color? link,
    Color? faint,
  }) =>
      ChatterColors(
        bubbleOut: bubbleOut ?? this.bubbleOut,
        onBubbleOut: onBubbleOut ?? this.onBubbleOut,
        bubbleIn: bubbleIn ?? this.bubbleIn,
        onBubbleIn: onBubbleIn ?? this.onBubbleIn,
        reach: reach ?? this.reach,
        link: link ?? this.link,
        faint: faint ?? this.faint,
      );

  @override
  ChatterColors lerp(ChatterColors? other, double t) {
    if (other == null) return this;
    return ChatterColors(
      bubbleOut: Color.lerp(bubbleOut, other.bubbleOut, t)!,
      onBubbleOut: Color.lerp(onBubbleOut, other.onBubbleOut, t)!,
      bubbleIn: Color.lerp(bubbleIn, other.bubbleIn, t)!,
      onBubbleIn: Color.lerp(onBubbleIn, other.onBubbleIn, t)!,
      reach: Color.lerp(reach, other.reach, t)!,
      link: Color.lerp(link, other.link, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
    );
  }
}
