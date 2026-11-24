import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/services/owner_access.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a wrong code leaves owner access off; the right one turns it on', () async {
    final exp = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    final client = MockClient((r) async => r.url.path == '/owner/redeem' && r.body.contains('good')
        ? http.Response('{"token":"o1.${'a' * 32}.$exp.sig"}', 200)
        : http.Response('{"error":"Invalid code"}', 403));
    final o = OwnerAccess.instance;
    await o.clear();
    expect(await o.redeem('bad', baseUrl: 'https://w.example.dev', client: client), isFalse);
    expect(o.active, isFalse);
    expect(OwnerAccess.token, isNull);
    expect(await o.redeem('good', baseUrl: 'https://w.example.dev', client: client), isTrue);
    expect(o.active, isTrue);
    await o.clear();
    expect(OwnerAccess.token, isNull);
  });

  test('a non-HTTPS backend is never contacted', () async {
    final client = MockClient((r) async => fail('must not be called'));
    expect(await OwnerAccess.instance.redeem('x', baseUrl: 'http://w.example.dev', client: client), isFalse);
  });
}
