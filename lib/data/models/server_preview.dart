/// Preview information gathered from a remote server on SSH connect.
///
/// Contains MOTD, OS details, uptime, memory, and disk usage parsed
/// from standard system commands (`uname -a`, `uptime`, `free -h`,
/// `df -h`, `/etc/os-release`).
class ServerPreview {
  /// Raw MOTD content from /etc/motd or login banner.
  final String? motd;

  /// Full uname output (kernel, hostname, arch).
  final String? uname;

  /// OS pretty name from /etc/os-release (e.g., "Ubuntu 22.04.3 LTS").
  final String? osName;

  /// System uptime string (e.g., "up 14 days, 3:22").
  final String? uptime;

  /// Memory usage summary (e.g., "3.8Gi / 7.7Gi").
  final String? memory;

  /// Root disk usage summary (e.g., "42G / 100G (45%)").
  final String? disk;

  /// Timestamp when this preview was fetched.
  final DateTime fetchedAt;

  const ServerPreview({
    this.motd,
    this.uname,
    this.osName,
    this.uptime,
    this.memory,
    this.disk,
    required this.fetchedAt,
  });

  /// Whether any meaningful data was collected.
  bool get hasData =>
      motd != null ||
      osName != null ||
      uptime != null ||
      memory != null ||
      disk != null;

  /// Short OS label for display in server cards.
  ///
  /// Prefers osName, falls back to uname kernel info.
  String? get displayOs => osName ?? uname;

  /// Compact one-line summary suitable for a server card subtitle.
  ///
  /// Format: "Ubuntu 22.04  ·  up 14d  ·  3.8G/7.7G RAM"
  String get summary {
    final parts = <String>[];
    if (osName != null) parts.add(osName!);
    if (uptime != null) parts.add(uptime!);
    if (memory != null) parts.add(memory!);
    return parts.join('  ·  ');
  }

  ServerPreview copyWith({
    String? motd,
    String? uname,
    String? osName,
    String? uptime,
    String? memory,
    String? disk,
    DateTime? fetchedAt,
  }) {
    return ServerPreview(
      motd: motd ?? this.motd,
      uname: uname ?? this.uname,
      osName: osName ?? this.osName,
      uptime: uptime ?? this.uptime,
      memory: memory ?? this.memory,
      disk: disk ?? this.disk,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }
}
