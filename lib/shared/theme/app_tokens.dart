import 'package:flutter/material.dart';

/// Layout constants used across Huddle. Keeping these in one place is what makes
/// the app feel like a single system rather than a pile of screens.
abstract final class Insets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double screen = 20;
}

abstract final class Radii {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius field = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheet = BorderRadius.vertical(top: Radius.circular(xl));
}

abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve standard = Curves.easeOutQuad;
}

/// Semantic colours that Material's [ColorScheme] has no slot for — status,
/// priority, and the per-person avatar palette.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.card,
    required this.hairline,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.neutral,
    required this.neutralContainer,
    required this.avatars,
    required this.shadow,
  });

  final Color canvas;
  final Color card;
  final Color hairline;

  final Color success;
  final Color onSuccess;
  final Color successContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;

  final Color danger;
  final Color onDanger;
  final Color dangerContainer;

  final Color info;
  final Color onInfo;
  final Color infoContainer;

  final Color neutral;
  final Color neutralContainer;

  final List<Color> avatars;
  final List<BoxShadow> shadow;

  static const light = AppPalette(
    canvas: Color(0xFFF6F6FB),
    card: Color(0xFFFFFFFF),
    hairline: Color(0x14101034),
    success: Color(0xFF157F4B),
    onSuccess: Color(0xFF0A3D24),
    successContainer: Color(0xFFDDF3E7),
    warning: Color(0xFF9A6300),
    onWarning: Color(0xFF4D3100),
    warningContainer: Color(0xFFFDEEDA),
    danger: Color(0xFFC0392F),
    onDanger: Color(0xFF5E1912),
    dangerContainer: Color(0xFFFCE6E4),
    info: Color(0xFF2563C9),
    onInfo: Color(0xFF10305F),
    infoContainer: Color(0xFFE3EDFD),
    neutral: Color(0xFF636478),
    neutralContainer: Color(0xFFEDEDF3),
    avatars: [
      Color(0xFF4F46E5),
      Color(0xFF0E9F6E),
      Color(0xFFDB6D28),
      Color(0xFF9333EA),
      Color(0xFF0891B2),
      Color(0xFFE11D6F),
    ],
    shadow: [
      BoxShadow(color: Color(0x0D101034), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x0F101034), blurRadius: 16, offset: Offset(0, 6)),
    ],
  );

  static const dark = AppPalette(
    canvas: Color(0xFF0E0E15),
    card: Color(0xFF191926),
    hairline: Color(0x1AFFFFFF),
    success: Color(0xFF4ADE80),
    onSuccess: Color(0xFFB9F5CF),
    successContainer: Color(0xFF13301F),
    warning: Color(0xFFFBBF4E),
    onWarning: Color(0xFFFBE4B4),
    warningContainer: Color(0xFF352511),
    danger: Color(0xFFFF7B6E),
    onDanger: Color(0xFFFFD2CC),
    dangerContainer: Color(0xFF3A1815),
    info: Color(0xFF6FA8FF),
    onInfo: Color(0xFFCFE0FF),
    infoContainer: Color(0xFF15243F),
    neutral: Color(0xFF9E9FB4),
    neutralContainer: Color(0xFF252534),
    avatars: [
      Color(0xFF8B84FF),
      Color(0xFF34D399),
      Color(0xFFFB923C),
      Color(0xFFC084FC),
      Color(0xFF22D3EE),
      Color(0xFFFB7185),
    ],
    shadow: [
      BoxShadow(color: Color(0x40000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x52000000), blurRadius: 18, offset: Offset(0, 8)),
    ],
  );

  /// Stable per-person colour so the same teammate is always the same hue.
  Color avatarFor(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return avatars[hash % avatars.length];
  }

  @override
  AppPalette copyWith({
    Color? canvas,
    Color? card,
    Color? hairline,
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? neutral,
    Color? neutralContainer,
    List<Color>? avatars,
    List<BoxShadow>? shadow,
  }) {
    return AppPalette(
      canvas: canvas ?? this.canvas,
      card: card ?? this.card,
      hairline: hairline ?? this.hairline,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      neutral: neutral ?? this.neutral,
      neutralContainer: neutralContainer ?? this.neutralContainer,
      avatars: avatars ?? this.avatars,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      card: Color.lerp(card, other.card, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      neutralContainer: Color.lerp(neutralContainer, other.neutralContainer, t)!,
      avatars: t < 0.5 ? avatars : other.avatars,
      shadow: BoxShadow.lerpList(shadow, other.shadow, t)!,
    );
  }
}

extension PaletteAccess on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}
