import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/repositories/session_repository.dart';
import 'package:murminal/data/services/tmux_controller.dart';

/// Manages the lifecycle of Murminal sessions.
///
/// Coordinates between [TmuxController] for remote tmux operations
/// and [SessionRepository] for local metadata persistence.
class SessionService {
  final TmuxController _tmux;
  final SessionRepository _repository;

  SessionService({
    required TmuxController tmuxController,
    required SessionRepository repository,
  })  : _tmux = tmuxController,
        _repository = repository;

  /// Create a new session on the given server with the specified engine.
  ///
  /// Creates a tmux session and launches the engine command inside it.
  /// Returns the newly created [Session] with status [SessionStatus.running].
  Future<Session> createSession({
    required String serverId,
    required String engine,
    required String name,
    String? launchCommand,
  }) async {
    final id = _generateId(name);
    final now = DateTime.now();

    // Create the tmux session, optionally running the engine launch command.
    await _tmux.createSession(id, command: launchCommand);

    final session = Session(
      id: id,
      serverId: serverId,
      engine: engine,
      name: name,
      status: SessionStatus.running,
      createdAt: now,
    );

    await _repository.save(session);
    return session;
  }

  /// Terminate a session by killing its tmux session.
  ///
  /// Updates the local status to [SessionStatus.done].
  Future<void> terminateSession(String sessionId) async {
    await _tmux.killSession(sessionId);
    await updateStatus(sessionId, SessionStatus.done);
  }

  /// List sessions, optionally filtered by [serverId].
  ///
  /// Combines locally persisted metadata with live tmux session state.
  /// Sessions that no longer exist in tmux are marked as [SessionStatus.done].
  ///
  /// When [serverId] is provided, only sessions for that server are returned.
  /// When omitted, sessions across all servers are returned.
  Future<List<Session>> listSessions({String? serverId}) async {
    final localSessions = serverId != null
        ? _repository.loadByServer(serverId)
        : _repository.loadAll();
    final tmuxSessions = await _tmux.listSessions();

    final tmuxNames = tmuxSessions.map((t) => t.name).toSet();

    final reconciled = <Session>[];
    for (final session in localSessions) {
      if (tmuxNames.contains(session.id)) {
        // Session is still alive in tmux.
        if (session.status == SessionStatus.done ||
            session.status == SessionStatus.error) {
          // Stale local status; update to running.
          final updated = session.copyWith(status: SessionStatus.running);
          await _repository.save(updated);
          reconciled.add(updated);
        } else {
          reconciled.add(session);
        }
      } else {
        // Session no longer exists in tmux.
        if (session.status == SessionStatus.running ||
            session.status == SessionStatus.idle) {
          final updated = session.copyWith(status: SessionStatus.done);
          await _repository.save(updated);
          reconciled.add(updated);
        } else {
          reconciled.add(session);
        }
      }
    }

    return reconciled;
  }

  /// Retrieve a single session by [sessionId].
  ///
  /// Returns null if no session with the given ID exists.
  Session? getSession(String sessionId) {
    return _repository.findById(sessionId);
  }

  /// Update the status of a session by [sessionId].
  Future<void> updateStatus(String sessionId, SessionStatus status) async {
    final session = _repository.findById(sessionId);
    if (session == null) return;

    final updated = session.copyWith(status: status);
    await _repository.save(updated);
  }

  /// Remove a terminated session from local persistence.
  Future<void> deleteSession(String sessionId) async {
    await _repository.delete(sessionId);
  }

  /// Generate a unique session identifier from the name and timestamp.
  String _generateId(String name) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitized = name.replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '-');
    return '$sanitized-$timestamp';
  }
}
