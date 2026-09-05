import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Print current timezone and time in Dart', () {
    final now = DateTime.now();
    print('DateTime.now(): $now');
    print('DateTime.now().isUtc: ${now.isUtc}');
    print('DateTime.now().timeZoneName: ${now.timeZoneName}');
    print('DateTime.now().timeZoneOffset: ${now.timeZoneOffset}');
    
    final parsedUtc = DateTime.parse('2026-07-15T23:58:37.650829Z');
    print('Parsed UTC string: $parsedUtc');
    print('Parsed UTC string isUtc: ${parsedUtc.isUtc}');
    print('Parsed UTC string toLocal(): ${parsedUtc.toLocal()}');
  });
}
