import 'package:flutter/material.dart';

/// Brand logo from [assets/branding/huddle.png].
///
/// Uses a square frame matching the asset (~1:1) so the mark is never
/// side-cropped when placed in a wide login column.
class HuddleLogo extends StatelessWidget {
  const HuddleLogo({
    super.key,
    this.size = 148,
  });

  /// Edge length of the square logo frame.
  final double size;

  static const assetPath = 'assets/branding/huddle.png';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Huddle',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
        ),
      ),
    );
  }
}
