import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:murminal/data/models/session.dart';

/// Persists session metadata locally using shared_preferences.
class SessionRepository {
  final SharedPreferences _prefs;

  /// Key used to store the JSON-encoded session list.
  static const _storageKey = 'murminal_sessions';

  SessionRepository(this._prefs);

  /// Load all persisted sessions.
  List<Session> loadAll() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Session.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Load sessions filtered by [serverId].
  List<Session> loadByServer(String serverId) {
    return loadAll().where((s) => s.serverId == serverId).toList();
  }

  /// Find a session by its [id]. Returns null if not found.
  Session? findById(String id) {
    final sessions = loadAll();
    try {
      return sessions.firstWhere((s) => s.id == id);
    } on StateError {
      return null;
    }
  }

  /// Save a session. Updates if exists, inserts if new.
  Future<void> save(Session session) async {
    final sessions = loadAll();
    final index = sessions.indexWhere((s) => s.id == session.id);

    if (index >= 0) {
      sessions[index] = session;
    } else {
      sessions.add(session);
    }

    await _persist(sessions);
  }

  /// Remove a session by its [id].
  Future<void> delete(String id) async {
    final sessions = loadAll();
    sessions.removeWhere((s) => s.id == id);
    await _persist(sessions);
  }

  /// Persist the session list to shared_preferences.
  Future<void> _persist(List<Session> sessions) async {
    final encoded = jsonEncode(sessions.map((s) => s.toJson()).toList());
    await _prefs.setString(_storageKey, encoded);
  }
}
