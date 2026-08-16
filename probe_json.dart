import 'dart:convert';

void main() {
  try {
    final payload = {'createdAt': DateTime.now()};
    print(jsonEncode(payload));
  } catch (e) {
    print('JSON_ERROR: $e');
  }
}
