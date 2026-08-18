import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:huddle/app.dart';

/// Drives the real widget tree: sign in, land on Today, move between tabs.
///
/// Note: [WidgetTester.pumpAndSettle] is deliberately avoided. The app has
/// intentionally looping animations (the live-meeting pulse, skeleton shimmer),
/// so the tree never reaches a settled state and pumpAndSettle would time out.
void main() {
  setUpAll(() {
    // Tests have no network; without this google_fonts throws while trying to
    // fetch Inter. Falls back to the bundled font instead.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: HuddleApp()));
    await tester.pump();
  }

  /// Signs in as [name] and waits out the fake auth + repository latency.
  Future<void> signInAs(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('login screen offers the team', (tester) async {
    await pumpApp(tester);

    expect(find.text('Huddle'), findsOneWidget);
    expect(find.text('Ajyothee Reddy'), findsOneWidget);
    expect(find.text('Aisha Khan'), findsOneWidget);
  });

  testWidgets('a manager signs in and sees the Team tab', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'Ajyothee Reddy');

    expect(find.textContaining('Ajyothee'), findsWidgets);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Team'), findsOneWidget);
  });

  testWidgets('a member signs in and the Team tab is hidden', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'Aisha Khan');

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    expect(
      find.text('Team'),
      findsNothing,
      reason: 'the Team tab is manager-only',
    );
  });

  testWidgets('navigating to Tasks shows the list and the New Task action',
      (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'Ajyothee Reddy');

    await tester.tap(find.text('Tasks'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('New Task'), findsOneWidget);
    expect(find.text('Search tasks'), findsOneWidget);
  });

  testWidgets('navigating to Expenses shows the summary and add action',
      (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'Ajyothee Reddy');

    await tester.tap(find.text('Expenses'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('OUTSTANDING'), findsOneWidget);
    expect(find.text('Add Expense'), findsOneWidget);
  });

  testWidgets('the manager team board groups work by person', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'Ajyothee Reddy');

    await tester.tap(find.text('Team'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Approvals'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Aisha Khan'), findsWidgets);
  });
}
