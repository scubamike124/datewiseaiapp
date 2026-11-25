import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/services/owner_access.dart';

class _MemStore implements OwnerStore {
  final m = <String, String>{};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String value) async => m[key] = value;
  @override
  Future<void> delete(String key) async => m.remove(key);
}

/// Runs only when the build is compiled with --dart-define=DW_OWNER_ACCESS=true (internal TestFlight).
const _needsFlag = 'needs --dart-define=DW_OWNER_ACCESS=true';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OwnerAccess.useStore(_MemStore());
  });

  // Public builds (flag off): the feature is inert in every path, and the Worker is never contacted.
  group('compiled out (public builds)', () {
    test('redeem is refused without contacting the Worker', () async {
      final client = MockClient((r) async => fail('must not be called'));
      expect(await OwnerAccess.instance.redeem('good', baseUrl: 'https://w.example.dev', client: client), isFalse);
      expect(OwnerAccess.instance.active, isFalse);
    }, skip: OwnerAccess.enabled ? 'runs only in public builds (flag off)' : null);

    test('a token in the store is never used, and load never contacts the Worker', () async {
      final store = _MemStore()..m['owner_token_v1'] = 'o1.${'c' * 32}.9999999999.sig';
      OwnerAccess.useStore(store);
      final client = MockClient((r) async => fail('must not be called'));
      await OwnerAccess.instance.load(baseUrl: 'https://w.example.dev', client: client);
      expect(OwnerAccess.instance.active, isFalse);
      expect(OwnerAccess.token, isNull);
    }, skip: OwnerAccess.enabled ? 'runs only in public builds (flag off)' : null);

    test('a token left by an earlier build is removed, not used', () async {
      SharedPreferences.setMockInitialValues({'owner_token_v1': 'o1.${'d' * 32}.9999999999.sig'});
      final store = _MemStore();
      OwnerAccess.useStore(store);
      await OwnerAccess.instance.load();
      expect((await SharedPreferences.getInstance()).getString('owner_token_v1'), isNull);
    }, skip: OwnerAccess.enabled ? 'runs only in public builds (flag off)' : null);
  });

  // Internal TestFlight builds (--dart-define=DW_OWNER_ACCESS=true).
  group('compiled in (internal TestFlight)', () {
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
    }, skip: OwnerAccess.enabled ? null : _needsFlag);

    test('a non-HTTPS backend is never contacted', () async {
      final client = MockClient((r) async => fail('must not be called'));
      expect(await OwnerAccess.instance.redeem('x', baseUrl: 'http://w.example.dev', client: client), isFalse);
    }, skip: OwnerAccess.enabled ? null : _needsFlag);

    test('a token saved by an earlier build moves into secure storage, and a newer Keychain token is kept', () async {
      final exp = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
      final oldTok = 'o1.${'b' * 32}.$exp.sig';
      final newTok = 'o1.${'e' * 32}.$exp.sig';
      SharedPreferences.setMockInitialValues({'owner_token_v1': oldTok});
      final store = _MemStore();
      OwnerAccess.useStore(store);
      final client = MockClient((r) async => http.Response('{"error":"x"}', 500));
      await OwnerAccess.instance.load(baseUrl: 'https://w.example.dev', client: client);
      expect(store.m['owner_token_v1'], oldTok);
      expect((await SharedPreferences.getInstance()).getString('owner_token_v1'), isNull);

      // A newer token already in the Keychain is never overwritten by a leftover old copy.
      SharedPreferences.setMockInitialValues({'owner_token_v1': oldTok});
      final store2 = _MemStore()..m['owner_token_v1'] = newTok;
      OwnerAccess.useStore(store2);
      await OwnerAccess.instance.load(baseUrl: 'https://w.example.dev', client: client);
      expect(store2.m['owner_token_v1'], newTok);
    }, skip: OwnerAccess.enabled ? null : _needsFlag);
  });
}
