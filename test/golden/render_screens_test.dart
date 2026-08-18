import 'package:flutter_test/flutter_test.dart';

/// Golden screenshots previously relied on offline Seed fixtures.
/// Re-enable with an API test harness when needed.
void main() {
  test('placeholder — golden screenshots require API fixtures', () {
    expect(true, isTrue);
  }, skip: 'Golden screenshots need a signed-in API session');
}
