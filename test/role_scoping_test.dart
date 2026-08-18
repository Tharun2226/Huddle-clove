import 'package:flutter_test/flutter_test.dart';

/// Offline Seed/mock role scoping was removed for production.
/// Role visibility is enforced by the Nest API and should be covered by
/// API integration tests.
void main() {
  test('placeholder — role scoping is API-backed', () {
    expect(true, isTrue);
  });
}
