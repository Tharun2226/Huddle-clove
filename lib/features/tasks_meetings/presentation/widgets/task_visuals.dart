import 'package:flutter/material.dart';

import '../../../../core/config/catalog_icons.dart';
import '../../../../core/config/org_config.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../domain/task.dart';

/// Static fallbacks when org catalog is empty (demo mode).
extension TaskStatusVisuals on TaskStatus {
  Color color(AppPalette p) => switch (this) {
        TaskStatus.todo => p.neutral,
        TaskStatus.inProgress => p.info,
        TaskStatus.inReview => p.warning,
        TaskStatus.done => p.success,
      };

  IconData get icon => switch (this) {
        TaskStatus.todo => Icons.circle_outlined,
        TaskStatus.inProgress => Icons.timelapse_rounded,
        TaskStatus.inReview => Icons.visibility_rounded,
        TaskStatus.done => Icons.check_circle_rounded,
      };

  String get shortLabel => switch (this) {
        TaskStatus.todo => 'To Do',
        TaskStatus.inProgress => 'Doing',
        TaskStatus.inReview => 'Review',
        TaskStatus.done => 'Done',
      };
}

extension TaskPriorityVisuals on TaskPriority {
  Color color(AppPalette p) => switch (this) {
        TaskPriority.urgent => p.danger,
        TaskPriority.high => p.warning,
        TaskPriority.normal => p.info,
        TaskPriority.low => p.neutral,
      };

  IconData get icon => switch (this) {
        TaskPriority.urgent => Icons.keyboard_double_arrow_up_rounded,
        TaskPriority.high => Icons.keyboard_arrow_up_rounded,
        TaskPriority.normal => Icons.remove_rounded,
        TaskPriority.low => Icons.keyboard_arrow_down_rounded,
      };
}

/// Resolve display fields from the org catalog (preferred) with enum fallback.
extension TaskCatalogVisuals on Task {
  OrgTaskStatus? orgStatus(OrgConfig config) {
    if (statusId.isNotEmpty) {
      final byId =
          config.taskStatuses.where((s) => s.id == statusId).firstOrNull;
      if (byId != null) return byId;
    }
    final slug = switch (status) {
      TaskStatus.todo => 'todo',
      TaskStatus.inProgress => 'in_progress',
      TaskStatus.inReview => 'in_review',
      TaskStatus.done => 'done',
    };
    return config.taskStatuses.where((s) => s.slug == slug).firstOrNull;
  }

  OrgTaskPriority? orgPriority(OrgConfig config) {
    if (priorityId.isNotEmpty) {
      final byId =
          config.taskPriorities.where((p) => p.id == priorityId).firstOrNull;
      if (byId != null) return byId;
    }
    return config.taskPriorities.where((p) => p.slug == priority.name).firstOrNull;
  }

  String statusLabel(OrgConfig config) =>
      orgStatus(config)?.name ?? status.label;

  String priorityLabel(OrgConfig config) =>
      orgPriority(config)?.name ?? priority.label;

  Color statusColor(OrgConfig config, AppPalette palette) {
    final org = orgStatus(config);
    if (org != null) return parseOrgColor(org.color, fallback: status.color(palette));
    return status.color(palette);
  }

  Color priorityColor(OrgConfig config, AppPalette palette) {
    final org = orgPriority(config);
    if (org != null) {
      return parseOrgColor(org.color, fallback: priority.color(palette));
    }
    return priority.color(palette);
  }

  IconData statusIcon(OrgConfig config) =>
      CatalogIcons.resolve(orgStatus(config)?.icon, fallback: status.icon);

  IconData priorityIcon(OrgConfig config) =>
      CatalogIcons.resolve(orgPriority(config)?.icon, fallback: priority.icon);

  bool isDoneIn(OrgConfig config) {
    final org = orgStatus(config);
    if (org != null) return org.isDone;
    return isDone;
  }
}

TaskStatus taskStatusFromOrg(OrgTaskStatus status) {
  if (status.isDone) return TaskStatus.done;
  return switch (status.slug) {
    'in_progress' || 'inProgress' => TaskStatus.inProgress,
    'in_review' || 'inReview' => TaskStatus.inReview,
    'done' => TaskStatus.done,
    _ => TaskStatus.todo,
  };
}

TaskPriority taskPriorityFromOrg(OrgTaskPriority priority) {
  return switch (priority.slug.toLowerCase()) {
    'urgent' => TaskPriority.urgent,
    'high' => TaskPriority.high,
    'low' => TaskPriority.low,
    _ => TaskPriority.normal,
  };
}
