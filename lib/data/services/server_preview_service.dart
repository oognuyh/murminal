import 'dart:developer' as developer;

import 'package:murminal/data/models/server_preview.dart';
import 'package:murminal/data/services/ssh_service.dart';

/// Service that gathers system preview information from a remote server.
///
/// Runs lightweight system commands over SSH to collect MOTD, OS info,
/// uptime, memory, and disk usage. All commands use `throwOnError: false`
/// since some may not be available on all systems.
class ServerPreviewService {
  static const _tag = 'ServerPreviewService';

  final SshService _ssh;

  ServerPreviewService(this._ssh);

  /// Fetch server preview information by running system info commands.
  ///
  /// Each command failure is handled gracefully — the corresponding
  /// field will be null if the command is unavailable or fails.
  Future<ServerPreview> fetchPreview() async {
    final results = await Future.wait([
      _fetchMotd(),
      _fetchUname(),
      _fetchOsName(),
      _fetchUptime(),
      _fetchMemory(),
      _fetchDisk(),
    ]);

    return ServerPreview(
      motd: results[0],
      uname: results[1],
      osName: results[2],
      uptime: results[3],
      memory: results[4],
      disk: results[5],
      fetchedAt: DateTime.now(),
    );
  }

  /// Read /etc/motd if it exists.
  Future<String?> _fetchMotd() async {
    try {
      final output = await _ssh.execute(
        'cat /etc/motd 2>/dev/null',
        throwOnError: false,
      );
      final trimmed = output.trim();
      return trimmed.isNotEmpty ? trimmed : null;
    } catch (e) {
      developer.log('Failed to fetch MOTD: $e', name: _tag);
      return null;
    }
  }

  /// Run `uname -a` for kernel and architecture info.
  Future<String?> _fetchUname() async {
    try {
      final output = await _ssh.execute(
        'uname -a',
        throwOnError: false,
      );
      final trimmed = output.trim();
      return trimmed.isNotEmpty ? trimmed : null;
    } catch (e) {
      developer.log('Failed to fetch uname: $e', name: _tag);
      return null;
    }
  }

  /// Parse PRETTY_NAME from /etc/os-release.
  Future<String?> _fetchOsName() async {
    try {
      final output = await _ssh.execute(
        'cat /etc/os-release 2>/dev/null',
        throwOnError: false,
      );
      return parseOsRelease(output);
    } catch (e) {
      developer.log('Failed to fetch OS name: $e', name: _tag);
      return null;
    }
  }

  /// Parse uptime into a compact string.
  Future<String?> _fetchUptime() async {
    try {
      final output = await _ssh.execute(
        'uptime',
        throwOnError: false,
      );
      return parseUptime(output);
    } catch (e) {
      developer.log('Failed to fetch uptime: $e', name: _tag);
      return null;
    }
  }

  /// Parse memory usage from `free -h`.
  Future<String?> _fetchMemory() async {
    try {
      final output = await _ssh.execute(
        'free -h 2>/dev/null',
        throwOnError: false,
      );
      return parseMemory(output);
    } catch (e) {
      developer.log('Failed to fetch memory: $e', name: _tag);
      return null;
    }
  }

  /// Parse root partition disk usage from `df -h /`.
  Future<String?> _fetchDisk() async {
    try {
      final output = await _ssh.execute(
        'df -h / 2>/dev/null',
        throwOnError: false,
      );
      return parseDisk(output);
    } catch (e) {
      developer.log('Failed to fetch disk: $e', name: _tag);
      return null;
    }
  }

  /// Extract PRETTY_NAME from os-release content.
  ///
  /// Looks for a line like: PRETTY_NAME="Ubuntu 22.04.3 LTS"
  /// Visible for testing.
  static String? parseOsRelease(String output) {
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('PRETTY_NAME=')) {
        var value = trimmed.substring('PRETTY_NAME='.length);
        // Remove surrounding quotes.
        if (value.startsWith('"') && value.endsWith('"')) {
          value = value.substring(1, value.length - 1);
        }
        return value.isNotEmpty ? value : null;
      }
    }
    return null;
  }

  /// Extract a compact uptime string from `uptime` output.
  ///
  /// Input example: " 14:22:01 up 14 days,  3:22,  2 users,  load average: 0.00"
  /// Output: "up 14 days, 3:22"
  /// Visible for testing.
  static String? parseUptime(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) return null;

    // Match the "up ... " segment before the user count.
    final upMatch = RegExp(r'up\s+(.+?),\s*\d+\s+user').firstMatch(trimmed);
    if (upMatch != null) {
      var uptimePart = upMatch.group(1)?.trim();
      if (uptimePart != null && uptimePart.isNotEmpty) {
        // Normalize multiple spaces to single space.
        uptimePart = uptimePart.replaceAll(RegExp(r'\s+'), ' ');
        return 'up $uptimePart';
      }
    }

    // Fallback: extract everything between "up" and "load".
    final fallback =
        RegExp(r'up\s+(.+?)\s*load').firstMatch(trimmed);
    if (fallback != null) {
      var part = fallback.group(1)?.trim() ?? '';
      // Remove trailing comma.
      if (part.endsWith(',')) part = part.substring(0, part.length - 1).trim();
      return part.isNotEmpty ? 'up $part' : null;
    }

    return null;
  }

  /// Parse the Mem line from `free -h` output.
  ///
  /// Input example:
  ///               total        used        free
  /// Mem:          7.7Gi       3.8Gi       1.2Gi
  /// Output: "3.8Gi / 7.7Gi"
  /// Visible for testing.
  static String? parseMemory(String output) {
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('Mem:')) {
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          final total = parts[1];
          final used = parts[2];
          return '$used / $total';
        }
      }
    }
    return null;
  }

  /// Parse root partition usage from `df -h /` output.
  ///
  /// Input example:
  /// Filesystem      Size  Used Avail Use% Mounted on
  /// /dev/sda1       100G   42G   53G  45% /
  /// Output: "42G / 100G (45%)"
  /// Visible for testing.
  static String? parseDisk(String output) {
    final lines = output.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      // Skip the header line.
      if (trimmed.startsWith('Filesystem')) continue;
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(RegExp(r'\s+'));
      // Expected: filesystem, size, used, avail, use%, mountpoint
      if (parts.length >= 5) {
        final size = parts[1];
        final used = parts[2];
        final usePct = parts[4];
        return '$used / $size ($usePct)';
      }
    }
    return null;
  }
}
