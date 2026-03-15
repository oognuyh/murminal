import 'package:murminal/data/services/ssh_service.dart';

/// Detected operating system type on the remote host.
enum RemoteOsType {
  /// Debian/Ubuntu-based Linux (uses apt).
  debian,

  /// Red Hat/CentOS/Fedora-based Linux (uses yum/dnf).
  redhat,

  /// Alpine Linux (uses apk).
  alpine,

  /// macOS (uses brew).
  macos,

  /// Unknown or unsupported OS.
  unknown,
}

/// Result of a tmux availability check on a remote server.
class TmuxCheckResult {
  /// Whether tmux is installed and available.
  final bool isInstalled;

  /// The tmux version string, if installed.
  final String? version;

  /// The detected remote OS type.
  final RemoteOsType osType;

  const TmuxCheckResult({
    required this.isInstalled,
    this.version,
    required this.osType,
  });
}

/// Service for detecting and installing tmux on remote hosts.
///
/// Detects the remote operating system and provides the correct
/// install command. Can execute auto-installation when the remote
/// user has sudo privileges.
class TmuxInstallService {
  final SshService _ssh;

  TmuxInstallService(this._ssh);

  /// Check tmux availability and detect the remote OS type.
  ///
  /// Returns a [TmuxCheckResult] with installation status,
  /// version string, and detected OS.
  Future<TmuxCheckResult> checkTmux() async {
    final osType = await detectOsType();

    try {
      final output = await _ssh.execute('tmux -V');
      final version = output.trim();
      if (version.isNotEmpty) {
        return TmuxCheckResult(
          isInstalled: true,
          version: version,
          osType: osType,
        );
      }
    } catch (_) {
      // tmux not found or command failed.
    }

    return TmuxCheckResult(
      isInstalled: false,
      osType: osType,
    );
  }

  /// Detect the operating system type on the remote host.
  Future<RemoteOsType> detectOsType() async {
    try {
      final uname = await _ssh.execute('uname -s');
      final system = uname.trim().toLowerCase();

      if (system == 'darwin') {
        return RemoteOsType.macos;
      }

      if (system == 'linux') {
        return await _detectLinuxDistro();
      }
    } catch (_) {
      // Fall through to unknown.
    }

    return RemoteOsType.unknown;
  }

  /// Detect the specific Linux distribution.
  Future<RemoteOsType> _detectLinuxDistro() async {
    try {
      final release = await _ssh.execute('cat /etc/os-release 2>/dev/null');
      final lower = release.toLowerCase();

      if (lower.contains('alpine')) {
        return RemoteOsType.alpine;
      }
      if (lower.contains('debian') ||
          lower.contains('ubuntu') ||
          lower.contains('mint')) {
        return RemoteOsType.debian;
      }
      if (lower.contains('rhel') ||
          lower.contains('centos') ||
          lower.contains('fedora') ||
          lower.contains('red hat') ||
          lower.contains('rocky') ||
          lower.contains('alma')) {
        return RemoteOsType.redhat;
      }
    } catch (_) {
      // Could not read os-release.
    }

    // Fallback: check for package managers.
    try {
      final aptCheck = await _ssh.execute('which apt-get 2>/dev/null');
      if (aptCheck.trim().isNotEmpty) return RemoteOsType.debian;
    } catch (_) {}

    try {
      final yumCheck = await _ssh.execute('which yum 2>/dev/null');
      if (yumCheck.trim().isNotEmpty) return RemoteOsType.redhat;
    } catch (_) {}

    try {
      final apkCheck = await _ssh.execute('which apk 2>/dev/null');
      if (apkCheck.trim().isNotEmpty) return RemoteOsType.alpine;
    } catch (_) {}

    return RemoteOsType.unknown;
  }

  /// Get the install command for the detected OS type.
  ///
  /// Returns null if the OS type is unknown.
  static String? getInstallCommand(RemoteOsType osType) {
    switch (osType) {
      case RemoteOsType.debian:
        return 'sudo apt-get update && sudo apt-get install -y tmux';
      case RemoteOsType.redhat:
        return 'sudo yum install -y tmux';
      case RemoteOsType.alpine:
        return 'sudo apk add tmux';
      case RemoteOsType.macos:
        return 'brew install tmux';
      case RemoteOsType.unknown:
        return null;
    }
  }

  /// Get a human-readable OS name for display.
  static String getOsDisplayName(RemoteOsType osType) {
    switch (osType) {
      case RemoteOsType.debian:
        return 'Debian/Ubuntu';
      case RemoteOsType.redhat:
        return 'RHEL/CentOS/Fedora';
      case RemoteOsType.alpine:
        return 'Alpine Linux';
      case RemoteOsType.macos:
        return 'macOS';
      case RemoteOsType.unknown:
        return 'Unknown OS';
    }
  }

  /// Attempt to auto-install tmux on the remote host.
  ///
  /// Returns true if installation succeeded (tmux is available
  /// after running the install command).
  /// Throws [TmuxInstallException] if the OS is not supported
  /// or the install command fails.
  Future<bool> installTmux(RemoteOsType osType) async {
    final command = getInstallCommand(osType);
    if (command == null) {
      throw TmuxInstallException(
        'Cannot auto-install tmux: unsupported operating system',
      );
    }

    try {
      await _ssh.execute(command);
    } catch (e) {
      throw TmuxInstallException(
        'Failed to install tmux: $e',
      );
    }

    // Verify installation succeeded.
    try {
      final output = await _ssh.execute('tmux -V');
      return output.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

/// Exception thrown when tmux installation fails.
class TmuxInstallException implements Exception {
  final String message;

  const TmuxInstallException(this.message);

  @override
  String toString() => 'TmuxInstallException: $message';
}
