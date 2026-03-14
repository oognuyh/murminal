import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/session.dart';

void main() {
  group('SessionStatus', () {
    test('fromString parses valid values', () {
      expect(SessionStatus.fromString('running'), SessionStatus.running);
      expect(SessionStatus.fromString('done'), SessionStatus.done);
      expect(SessionStatus.fromString('idle'), SessionStatus.idle);
      expect(SessionStatus.fromString('error'), SessionStatus.error);
    });

    test('fromString defaults to idle for unknown values', () {
      expect(SessionStatus.fromString('unknown'), SessionStatus.idle);
      expect(SessionStatus.fromString(''), SessionStatus.idle);
    });
  });

  group('Session', () {
    final now = DateTime(2025, 6, 15, 10, 30);

    Session createSession({
      String id = 'test-123',
      String serverId = 'server-1',
      String engine = 'claude',
      String name = 'dev-session',
      SessionStatus status = SessionStatus.running,
      DateTime? createdAt,
      String? worktreePath,
    }) {
      return Session(
        id: id,
        serverId: serverId,
        engine: engine,
        name: name,
        status: status,
        createdAt: createdAt ?? now,
        worktreePath: worktreePath,
      );
    }

    test('toJson serializes all fields', () {
      final session = createSession(worktreePath: '/home/user/project');
      final json = session.toJson();

      expect(json['id'], 'test-123');
      expect(json['server_id'], 'server-1');
      expect(json['engine'], 'claude');
      expect(json['name'], 'dev-session');
      expect(json['status'], 'running');
      expect(json['created_at'], now.toIso8601String());
      expect(json['worktree_path'], '/home/user/project');
    });

    test('toJson omits worktreePath when null', () {
      final session = createSession();
      final json = session.toJson();
      expect(json.containsKey('worktree_path'), isFalse);
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'id': 'test-123',
        'server_id': 'server-1',
        'engine': 'claude',
        'name': 'dev-session',
        'status': 'running',
        'created_at': now.toIso8601String(),
        'worktree_path': '/tmp/work',
      };

      final session = Session.fromJson(json);
      expect(session.id, 'test-123');
      expect(session.serverId, 'server-1');
      expect(session.engine, 'claude');
      expect(session.name, 'dev-session');
      expect(session.status, SessionStatus.running);
      expect(session.createdAt, now);
      expect(session.worktreePath, '/tmp/work');
    });

    test('roundtrip JSON serialization preserves data', () {
      final original = createSession(worktreePath: '/home/user/work');
      final json = original.toJson();
      final restored = Session.fromJson(json);
      expect(restored, equals(original));
    });

    test('parse deserializes from JSON string', () {
      final session = createSession();
      final jsonString = jsonEncode(session.toJson());
      final parsed = Session.parse(jsonString);
      expect(parsed, equals(session));
    });

    test('copyWith creates modified copy', () {
      final session = createSession();
      final updated = session.copyWith(status: SessionStatus.done);

      expect(updated.id, session.id);
      expect(updated.status, SessionStatus.done);
      expect(updated.name, session.name);
    });

    test('copyWith preserves all fields when no arguments given', () {
      final session = createSession(worktreePath: '/tmp');
      final copy = session.copyWith();
      expect(copy, equals(session));
    });

    test('equality works for identical sessions', () {
      final a = createSession();
      final b = createSession();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality for different ids', () {
      final a = createSession(id: 'a');
      final b = createSession(id: 'b');
      expect(a, isNot(equals(b)));
    });

    test('toString contains key fields', () {
      final session = createSession();
      final str = session.toString();
      expect(str, contains('test-123'));
      expect(str, contains('claude'));
      expect(str, contains('running'));
    });
  });
}
