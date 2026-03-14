import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/repositories/session_repository.dart';

void main() {
  late SessionRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SessionRepository> createRepository(
      {Map<String, Object>? initial}) async {
    if (initial != null) {
      SharedPreferences.setMockInitialValues(initial);
    }
    final prefs = await SharedPreferences.getInstance();
    return SessionRepository(prefs);
  }

  Session createSession({
    String id = 'test-1',
    String serverId = 'server-1',
    String engine = 'claude',
    String name = 'dev',
    SessionStatus status = SessionStatus.running,
  }) {
    return Session(
      id: id,
      serverId: serverId,
      engine: engine,
      name: name,
      status: status,
      createdAt: DateTime(2025, 6, 15),
    );
  }

  group('SessionRepository', () {
    test('loadAll returns empty list when no data stored', () async {
      repository = await createRepository();
      expect(repository.loadAll(), isEmpty);
    });

    test('save and loadAll roundtrip', () async {
      repository = await createRepository();
      final session = createSession();

      await repository.save(session);
      final loaded = repository.loadAll();

      expect(loaded, hasLength(1));
      expect(loaded[0], equals(session));
    });

    test('save updates existing session', () async {
      repository = await createRepository();
      final session = createSession();
      await repository.save(session);

      final updated = session.copyWith(status: SessionStatus.done);
      await repository.save(updated);

      final loaded = repository.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded[0].status, SessionStatus.done);
    });

    test('loadByServer filters by serverId', () async {
      repository = await createRepository();
      await repository.save(createSession(id: 'a', serverId: 'server-1'));
      await repository.save(createSession(id: 'b', serverId: 'server-2'));
      await repository.save(createSession(id: 'c', serverId: 'server-1'));

      final filtered = repository.loadByServer('server-1');
      expect(filtered, hasLength(2));
      expect(filtered.every((s) => s.serverId == 'server-1'), isTrue);
    });

    test('findById returns session when found', () async {
      repository = await createRepository();
      final session = createSession(id: 'find-me');
      await repository.save(session);

      final found = repository.findById('find-me');
      expect(found, isNotNull);
      expect(found!.id, 'find-me');
    });

    test('findById returns null when not found', () async {
      repository = await createRepository();
      expect(repository.findById('nonexistent'), isNull);
    });

    test('delete removes session', () async {
      repository = await createRepository();
      await repository.save(createSession(id: 'to-delete'));
      await repository.save(createSession(id: 'to-keep'));

      await repository.delete('to-delete');

      final loaded = repository.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded[0].id, 'to-keep');
    });

    test('loads sessions from pre-existing shared_preferences data', () async {
      final session = createSession();
      final encoded = jsonEncode([session.toJson()]);

      repository = await createRepository(
        initial: {'murminal_sessions': encoded},
      );

      final loaded = repository.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded[0].id, session.id);
    });
  });
}
