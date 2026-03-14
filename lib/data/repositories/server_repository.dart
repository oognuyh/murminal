import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:murminal/data/models/server_config.dart';

/// Key used to store the server configuration list in shared_preferences.
const _storageKey = 'server_configs';

/// Repository for persisting SSH server configurations.
///
/// Uses [SharedPreferences] to store a JSON-encoded list of [ServerConfig]s.
class ServerRepository {
  final SharedPreferences _prefs;

  ServerRepository(this._prefs);

  /// Load all saved server configurations.
  List<ServerConfig> getAll() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null) return [];

    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Find a server configuration by its id.
  ServerConfig? getById(String id) {
    final all = getAll();
    for (final config in all) {
      if (config.id == id) return config;
    }
    return null;
  }

  /// Save a new server configuration.
  Future<void> add(ServerConfig config) async {
    final all = getAll();
    all.add(config);
    await _persist(all);
  }

  /// Update an existing server configuration by id.
  Future<void> update(ServerConfig config) async {
    final all = getAll();
    final index = all.indexWhere((c) => c.id == config.id);
    if (index == -1) {
      throw StateError('ServerConfig with id ${config.id} not found');
    }
    all[index] = config;
    await _persist(all);
  }

  /// Delete a server configuration by id.
  Future<void> delete(String id) async {
    final all = getAll();
    all.removeWhere((c) => c.id == id);
    await _persist(all);
  }

  /// Save or update a server configuration.
  ///
  /// If a configuration with the same id exists, it is replaced.
  /// Otherwise, the configuration is appended.
  Future<void> save(ServerConfig config) async {
    final all = getAll();
    final index = all.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      all[index] = config;
    } else {
      all.add(config);
    }
    await _persist(all);
  }

  Future<void> _persist(List<ServerConfig> configs) async {
    final json = jsonEncode(configs.map(_toJson).toList());
    await _prefs.setString(_storageKey, json);
  }
}

Map<String, dynamic> _toJson(ServerConfig config) {
  final map = <String, dynamic>{
    'id': config.id,
    'label': config.label,
    'host': config.host,
    'port': config.port,
    'username': config.username,
    'createdAt': config.createdAt.toIso8601String(),
  };

  if (config.lastConnectedAt != null) {
    map['lastConnectedAt'] = config.lastConnectedAt!.toIso8601String();
  }
  if (config.jumpHost != null) {
    map['jumpHost'] = config.jumpHost;
  }

  switch (config.auth) {
    case PasswordAuth(password: final password):
      map['authType'] = 'password';
      map['password'] = password;
    case KeyAuth(privateKeyPath: final keyPath, passphrase: final passphrase):
      map['authType'] = 'key';
      map['privateKeyPath'] = keyPath;
      if (passphrase != null) {
        map['passphrase'] = passphrase;
      }
  }

  return map;
}

ServerConfig _fromJson(Map<String, dynamic> json) {
  final AuthMethod auth;
  final authType = json['authType'] as String;

  if (authType == 'password') {
    auth = PasswordAuth(password: json['password'] as String);
  } else {
    auth = KeyAuth(
      privateKeyPath: json['privateKeyPath'] as String,
      passphrase: json['passphrase'] as String?,
    );
  }

  return ServerConfig(
    id: json['id'] as String,
    label: json['label'] as String,
    host: json['host'] as String,
    port: json['port'] as int? ?? 22,
    username: json['username'] as String,
    auth: auth,
    jumpHost: json['jumpHost'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastConnectedAt: json['lastConnectedAt'] != null
        ? DateTime.parse(json['lastConnectedAt'] as String)
        : null,
  );
}
