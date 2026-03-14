import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/ssh_key.dart';
import 'package:murminal/data/services/ssh_key_service.dart';

/// In-memory fake for FlutterSecureStorage used in unit tests.
class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _store[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map.from(_store);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.clear();
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _store.containsKey(key);
  }

  @override
  Future<bool> isCupertinoProtectedDataAvailable() async => true;

  @override
  Stream<bool> get onCupertinoProtectedDataAvailabilityChanged =>
      const Stream.empty();

  @override
  IOSOptions get iOptions => IOSOptions.defaultOptions;

  @override
  AndroidOptions get aOptions => AndroidOptions.defaultOptions;

  @override
  LinuxOptions get lOptions => LinuxOptions.defaultOptions;

  @override
  WebOptions get webOptions => WebOptions.defaultOptions;

  @override
  MacOsOptions get mOptions => MacOsOptions.defaultOptions;

  @override
  WindowsOptions get wOptions => WindowsOptions.defaultOptions;

  @override
  void registerListener({
    required String key,
    required ValueChanged<String?> listener,
  }) {}

  @override
  void unregisterListener({
    required String key,
    required ValueChanged<String?> listener,
  }) {}

  @override
  void unregisterAllListenersForKey({required String key}) {}

  @override
  void unregisterAllListeners() {}
}

void main() {
  late FakeSecureStorage fakeStorage;
  late SshKeyService service;

  setUp(() {
    fakeStorage = FakeSecureStorage();
    service = SshKeyService(storage: fakeStorage);
  });

  group('SshKeyService', () {
    group('generateKey', () {
      test('generates an Ed25519 key and stores it', () async {
        final key = await service.generateKey(name: 'test-key');

        expect(key.name, 'test-key');
        expect(key.type, SshKeyType.ed25519);
        expect(key.publicKey, startsWith('ssh-ed25519 '));
        expect(key.publicKey, endsWith(' test-key'));
        expect(key.id, isNotEmpty);
        expect(key.createdAt, isA<DateTime>());
      });

      test('stores private key in secure storage', () async {
        final key = await service.generateKey(name: 'stored-key');

        final pem = await service.getPrivateKey(key.id);
        expect(pem, isNotNull);
        expect(pem, contains('OPENSSH PRIVATE KEY'));
      });

      test('generated key can be parsed by dartssh2', () async {
        final key = await service.generateKey(name: 'parseable-key');

        final keyPairs = await service.getKeyPairs(key.id);
        expect(keyPairs, isNotEmpty);
        expect(keyPairs.first.type, 'ssh-ed25519');
      });

      test('generates unique keys each time', () async {
        final key1 = await service.generateKey(name: 'key-1');
        final key2 = await service.generateKey(name: 'key-2');

        expect(key1.id, isNot(key2.id));
        expect(key1.publicKey, isNot(key2.publicKey));
      });
    });

    group('listKeys', () {
      test('returns empty list when no keys exist', () async {
        final keys = await service.listKeys();
        expect(keys, isEmpty);
      });

      test('returns all generated keys', () async {
        await service.generateKey(name: 'key-a');
        await service.generateKey(name: 'key-b');

        final keys = await service.listKeys();
        expect(keys, hasLength(2));
        expect(keys.map((k) => k.name), containsAll(['key-a', 'key-b']));
      });
    });

    group('deleteKey', () {
      test('removes key from list and storage', () async {
        final key = await service.generateKey(name: 'to-delete');

        await service.deleteKey(key.id);

        final keys = await service.listKeys();
        expect(keys, isEmpty);

        final pem = await service.getPrivateKey(key.id);
        expect(pem, isNull);
      });

      test('does not affect other keys', () async {
        final key1 = await service.generateKey(name: 'keep');
        final key2 = await service.generateKey(name: 'delete');

        await service.deleteKey(key2.id);

        final keys = await service.listKeys();
        expect(keys, hasLength(1));
        expect(keys.first.id, key1.id);
      });
    });

    group('importKey', () {
      test('imports a PEM key and stores it', () async {
        // First generate a key to get valid PEM content.
        final generated = await service.generateKey(name: 'source');
        final pem = await service.getPrivateKey(generated.id);

        final imported = await service.importKey(
          name: 'imported-key',
          pemContent: pem!,
        );

        expect(imported.name, 'imported-key');
        expect(imported.type, SshKeyType.ed25519);
        expect(imported.publicKey, contains('ssh-ed25519'));
      });

      test('throws on invalid PEM content', () async {
        expect(
          () => service.importKey(name: 'bad', pemContent: 'not-a-pem'),
          throwsA(isA<Error>()),
        );
      });
    });

    group('getKeyPairs', () {
      test('returns dartssh2 key pairs for authentication', () async {
        final key = await service.generateKey(name: 'auth-key');

        final pairs = await service.getKeyPairs(key.id);
        expect(pairs, hasLength(1));
        expect(pairs.first.type, 'ssh-ed25519');
      });

      test('throws when key ID does not exist', () async {
        expect(
          () => service.getKeyPairs('nonexistent'),
          throwsA(isA<StateError>()),
        );
      });
    });
  });

  group('SshKey model', () {
    test('serializes to JSON and back', () {
      final key = SshKey(
        id: 'test-id',
        name: 'my-key',
        publicKey: 'ssh-ed25519 AAAA my-key',
        type: SshKeyType.ed25519,
        createdAt: DateTime(2025, 1, 15, 10, 30),
      );

      final json = key.toJson();
      final restored = SshKey.fromJson(json);

      expect(restored.id, key.id);
      expect(restored.name, key.name);
      expect(restored.publicKey, key.publicKey);
      expect(restored.type, key.type);
      expect(restored.createdAt, key.createdAt);
    });

    test('equality is based on id', () {
      final key1 = SshKey(
        id: 'same-id',
        name: 'name-1',
        publicKey: 'key-1',
        type: SshKeyType.ed25519,
        createdAt: DateTime(2025, 1, 1),
      );
      final key2 = SshKey(
        id: 'same-id',
        name: 'name-2',
        publicKey: 'key-2',
        type: SshKeyType.ed25519,
        createdAt: DateTime(2025, 6, 1),
      );

      expect(key1, equals(key2));
      expect(key1.hashCode, key2.hashCode);
    });

    test('copyWith creates updated instance', () {
      final original = SshKey(
        id: 'id-1',
        name: 'original',
        publicKey: 'pub',
        type: SshKeyType.ed25519,
        createdAt: DateTime(2025, 1, 1),
      );

      final updated = original.copyWith(name: 'updated');
      expect(updated.name, 'updated');
      expect(updated.id, original.id);
      expect(updated.publicKey, original.publicKey);
    });

    test('toString includes key info', () {
      final key = SshKey(
        id: 'id-1',
        name: 'my-key',
        publicKey: 'pub',
        type: SshKeyType.ed25519,
        createdAt: DateTime(2025, 1, 1),
      );

      expect(key.toString(), contains('my-key'));
      expect(key.toString(), contains('ed25519'));
    });
  });
}
