import 'package:flutter/material.dart';

/// Shared icon catalog for org task statuses and priorities.
class CatalogIcons {
  CatalogIcons._();

  static const entries = <({String key, IconData icon, String label})>[
    (key: 'circle_outlined', icon: Icons.circle_outlined, label: 'Circle'),
    (key: 'radio_unchecked', icon: Icons.radio_button_unchecked, label: 'Radio'),
    (key: 'timelapse', icon: Icons.timelapse_rounded, label: 'Progress'),
    (key: 'hourglass', icon: Icons.hourglass_top_rounded, label: 'Hourglass'),
    (key: 'visibility', icon: Icons.visibility_rounded, label: 'Review'),
    (key: 'check_circle', icon: Icons.check_circle_rounded, label: 'Check'),
    (key: 'done_all', icon: Icons.done_all_rounded, label: 'Done all'),
    (key: 'pause_circle', icon: Icons.pause_circle_outline_rounded, label: 'Pause'),
    (key: 'flag', icon: Icons.flag_rounded, label: 'Flag'),
    (key: 'bolt', icon: Icons.bolt_rounded, label: 'Bolt'),
    (key: 'priority_high', icon: Icons.priority_high_rounded, label: 'Priority'),
    (key: 'arrow_upward', icon: Icons.keyboard_arrow_up_rounded, label: 'Up'),
    (key: 'double_up', icon: Icons.keyboard_double_arrow_up_rounded, label: 'Double up'),
    (key: 'arrow_downward', icon: Icons.keyboard_arrow_down_rounded, label: 'Down'),
    (key: 'remove', icon: Icons.remove_rounded, label: 'Neutral'),
    (key: 'star', icon: Icons.star_rounded, label: 'Star'),
    (key: 'bookmark', icon: Icons.bookmark_rounded, label: 'Bookmark'),
    (key: 'label', icon: Icons.label_rounded, label: 'Label'),
    (key: 'fire', icon: Icons.local_fire_department_rounded, label: 'Fire'),
    (key: 'warning', icon: Icons.warning_amber_rounded, label: 'Warning'),
  ];

  static IconData resolve(String? key, {IconData fallback = Icons.circle_outlined}) {
    if (key == null || key.isEmpty) return fallback;
    for (final e in entries) {
      if (e.key == key) return e.icon;
    }
    return fallback;
  }
}

Color parseOrgColor(String hex, {Color fallback = const Color(0xFF6B7280)}) {
  var value = hex.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return fallback;
  try {
    return Color(int.parse(value, radix: 16));
  } catch (_) {
    return fallback;
  }
}
