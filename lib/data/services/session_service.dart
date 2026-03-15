import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/repositories/session_repository.dart';
import 'package:murminal/data/services/ssh_connection_pool.dart';
import 'package:murminal/data/services/tmux_controller.dart';

/// Manages the lifecycle of Murminal sessions.
///
/// Coordinates between [SshConnectionPool] for per-server SSH connections,
/// [TmuxController] for remote tmux operations, and [SessionRepository]
/// for local metadata persistence.
class SessionService {
  final SshConnectionPool _pool;
  final SessionRepository _repository;

  /// Factory for creating [TmuxController] instances from an SSH service.
  ///
  /// Injectable for testing; defaults to the standard constructor.
  final TmuxController Function(dynamic ssh) _tmuxFactory;

  SessionService({
    required SshConnectionPool pool,
    required SessionRepository repository,
    TmuxController Function(dynamic ssh)? tmuxFactory,
  })  : _pool = pool,
        _repository = repository,
        _tmuxFactory = tmuxFactory ?? ((ssh) => TmuxController(ssh));

  /// Create a new session on the given server with the specified engine.
  ///
  /// Obtains an SSH connection from the pool for [serverId], creates a
  /// tmux session, and launches the engine command inside it.
  /// Returns the newly created [Session] with status [SessionStatus.running].
  ///
  /// Throws [StateError] if no server config is registered in the pool
  /// for [serverId], or if the SSH connection fails.
  Future<Session> createSession({
    required String serverId,
    required String engine,
    required String name,
    String? launchCommand,
    String? worktreePath,
    String? worktreeBranch,
  }) async {
    final ssh = await _pool.getConnection(serverId);
    final tmux = _tmuxFactory(ssh);
    final id = _generateId(name);
    final now = DateTime.now();

    // Create the tmux session, optionally running the engine launch command.
    await tmux.createSession(id, command: launchCommand);

    final session = Session(
      id: id,
      serverId: serverId,
      engine: engine,
      name: name,
      status: SessionStatus.running,
      createdAt: now,
      worktreePath: worktreePath,
      worktreeBranch: worktreeBranch,
    );

    await _repository.save(session);
    return session;
  }

  /// Terminate a session by killing its tmux session.
  ///
  /// Obtains the SSH connection for the session's server from the pool.
  /// Updates the local status to [SessionStatus.done].
  Future<void> terminateSession(String sessionId) async {
    final session = _repository.findById(sessionId);
    if (session == null) return;

    final ssh = await _pool.getConnection(session.serverId);
    final tmux = _tmuxFactory(ssh);
    await tmux.killSession(sessionId);
    await updateStatus(sessionId, SessionStatus.done);
  }

  /// List sessions, optionally filtered by [serverId].
  ///
  /// Combines locally persisted metadata with live tmux session state.
  /// Sessions that no longer exist in tmux are marked as [SessionStatus.done].
  ///
  /// When [serverId] is provided, only sessions for that server are returned
  /// and tmux reconciliation uses that server's SSH connection.
  /// When omitted, sessions across all servers are returned but tmux
  /// reconciliation is skipped (local state only).
  Future<List<Session>> listSessions({String? serverId}) async {
    final localSessions = serverId != null
        ? _repository.loadByServer(serverId)
        : _repository.loadAll();

    // When listing for a specific server, reconcile with live tmux state.
    if (serverId != null && _pool.isConnected(serverId)) {
      final ssh = await _pool.getConnection(serverId);
      final tmux = _tmuxFactory(ssh);
      final tmuxSessions = await tmux.listSessions();
      return _reconcileSessions(localSessions, tmuxSessions);
    }

    return localSessions;
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

  /// Reconcile local sessions with live tmux session state.
  Future<List<Session>> _reconcileSessions(
    List<Session> localSessions,
    List<dynamic> tmuxSessions,
  ) async {
    final tmuxNames = tmuxSessions.map((t) => t.name as String).toSet();
    final reconciled = <Session>[];

    for (final session in localSessions) {
      if (tmuxNames.contains(session.id)) {
        if (session.status == SessionStatus.done ||
            session.status == SessionStatus.error) {
          final updated = session.copyWith(status: SessionStatus.running);
          await _repository.save(updated);
          reconciled.add(updated);
        } else {
          reconciled.add(session);
        }
      } else {
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

  /// Generate a unique session identifier from the name and timestamp.
  String _generateId(String name) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitized = name.replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '-');
    return '$sanitized-$timestamp';
  }
}
