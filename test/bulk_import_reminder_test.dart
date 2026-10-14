import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huddle/features/tasks_meetings/domain/task.dart';
import 'package:huddle/features/tasks_meetings/presentation/widgets/task_import_excel.dart';
import 'package:huddle/features/tasks_meetings/presentation/widgets/task_schedule_paste.dart';

void main() {
  group('pasted schedule tasks are visible to the owner', () {
    final ownedExternalOnly = Task(
      id: 't1',
      title: 'Visit of Nidamarru Unit',
      assigneeId: 'me',
      createdAt: DateTime(2026, 10, 14),
      externalAssignees: const ['Additional commissioner'],
    );

    test('owner sees a task that lists only outside people', () {
      expect(ownedExternalOnly.isVisibleTo('me'), isTrue);
    });

    test('other members still do not', () {
      expect(ownedExternalOnly.isVisibleTo('someone-else'), isFalse);
    });

    test('normal assignment still works', () {
      final assigned = Task(
        id: 't2',
        title: 'Grid offices',
        assigneeId: 'boss',
        assigneeIds: const ['boss', 'me'],
        createdAt: DateTime(2026, 10, 14),
      );
      expect(assigned.isVisibleTo('me'), isTrue);
      expect(assigned.isVisibleTo('stranger'), isFalse);
    });
  });

  test('created ids line up with rows, skipping failed rows', () {
    expect(
      createdIdsByRow(
        rowCount: 4,
        createdIds: const ['a', 'b', 'c'],
        failedRows: const {2},
      ),
      ['a', null, 'b', 'c'],
    );
    expect(
      createdIdsByRow(rowCount: 2, createdIds: const [], failedRows: const {}),
      [null, null],
    );
  });

  testWidgets('each pasted task gets its own reminder, plus "for all"',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final rows = parseSchedulePasteText('''
Meeting on 15.10.2026 (Thursday)

Additional commissioner sir Schedule

9:00 AM - TC of the Commissioner sir
11:00 AM - Visit of Nidamarru Unit
''');

    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: taskImportReviewSheetForTest(rows)),
      ),
    );

    // One picker per row + the "for all" shortcut.
    expect(find.text('Remind me'), findsNWidgets(2));
    expect(find.text('Remind me for all tasks (this phone)'), findsOneWidget);
    expect(find.text('Import 2 tasks'), findsOneWidget);
    expect(find.text('Alarm'), findsNothing);

    // Set only the first task: 15 min before, alarm.
    await tester.tap(find.text('No reminder').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 minutes before').last);
    await tester.pumpAndSettle();
    expect(find.text('Alarm'), findsOneWidget);
    await tester.tap(find.text('Alarm'));
    await tester.pumpAndSettle();
    expect(find.text('Import 2 tasks · 1 with reminders'), findsOneWidget);

    // "For all" overwrites every row.
    await tester.tap(find.text('No reminder').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 minutes before').last);
    await tester.pumpAndSettle();
    expect(find.text('5 minutes before'), findsNWidgets(3));
    expect(find.text('Import 2 tasks · 2 with reminders'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
