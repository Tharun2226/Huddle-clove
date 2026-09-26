import "package:flutter_test/flutter_test.dart";
import "package:huddle/features/tasks_meetings/presentation/widgets/task_schedule_paste.dart";

void main() {
  test("parses full commissioner day", () {
    const raw = """
Meeting on 11.08.2026 (Friday)

Additional commissioner sir Schedule

9:00 AM -  Teleconference on E3, E13, E15 

9:15 AM - Teleconfernece with SDCs of LPS -  2.0

9:30 AM - Teleconference with SDCs of LPS - 1.0

10:30 AM - Meeting with PVK Bhaskar, CE and Paleswarao, GD, Accounts on CITIIS works

11:00 AM - Visit of Nowluru Unit (Tentative)

11:30 PM  - Attending Court 

2:30 PM - Attending the Lottery 

3:00 PM -  Meeting with Director, Lands, CC & CR and Jayashree, GRM on Dissatisfied Grievances Analysis

3:30 PM - Meeting with Uma, Director, Strategy and Bhagya Rekha, Director, Lands on verification of World Bank Lands

4:00 PM - Visit of Kuragallu Unit 

5:00 PM - Visit of Nidamarru Unit

7:00 PM - Meeting with Commissioner sir on Decission Points
""";
    final rows = parseSchedulePasteText(raw);
    expect(rows.length, 12);
    expect(rows.every((r) => r.assignees == "Additional commissioner"), isTrue);
    expect(rows[5].dueDate.hour, 23); // 11:30 PM as written
    expect(rows.last.title, "Meeting with Commissioner sir on Decission Points");
  });

  test('strips bold asterisks from paste', () {
    const raw = '''
*Meeting on 11.08.2026 (Friday)*

*Additional commissioner sir Schedule*

*9:00 AM* - *Teleconference on E3, E13, E15*
9:15 AM - Teleconfernece with SDCs of LPS - 2.0
''';
    final rows = parseSchedulePasteText(raw);
    expect(rows.length, 2);
    expect(rows.first.assignees, 'Additional commissioner');
    expect(rows.first.title, 'Teleconference on E3, E13, E15');
    expect(rows.first.title.contains('*'), isFalse);
    expect(rows.first.dueDate, DateTime(2026, 8, 11, 9, 0));
  });
}
