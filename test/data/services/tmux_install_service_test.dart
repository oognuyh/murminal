import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/services/ssh_service.dart';
import 'package:murminal/data/services/tmux_install_service.dart';

/// Manual mock for SshService to avoid build_runner dependency.
class MockSshService extends SshService {
  final List<String> commands = [];
  String Function(String command)? _handler;
  bool Function(String command)? _errorHandler;

  void onExecute(String Function(String command) handler) {
    _handler = handler;
    _errorHandler = null;
  }

  /// Configure the mock to throw for specific commands.
  void onExecuteWithErrors({
    required String Function(String command) handler,
    bool Function(String command)? shouldThrow,
  }) {
    _handler = handler;
    _errorHandler = shouldThrow;
  }

  @override
  Future<String> execute(String command, {bool throwOnError = true}) async {
    commands.add(command);
    if (_errorHandler != null && _errorHandler!(command)) {
      throw Exception('Command failed: $command');
    }
    if (_handler != null) return _handler!(command);
    return '';
  }

  @override
  bool get isConnected => true;
}

void main() {
  late MockSshService mockSsh;
  late TmuxInstallService service;

  setUp(() {
    mockSsh = MockSshService();
    service = TmuxInstallService(mockSsh);
  });

  group('TmuxInstallService', () {
    group('checkTmux', () {
      test('returns installed with version when tmux is found', () async {
        mockSsh.onExecute((cmd) {
          if (cmd == 'tmux -V') return 'tmux 3.4';
          if (cmd == 'uname -s') return 'Linux';
          if (cmd.contains('os-release')) return 'ID=ubuntu';
          return '';
        });

        final result = await service.checkTmux();
        expect(result.isInstalled, isTrue);
        expect(result.version, 'tmux 3.4');
        expect(result.osType, RemoteOsType.debian);
      });

      test('returns not installed when tmux command fails', () async {
        mockSsh.onExecuteWithErrors(
          handler: (cmd) {
            if (cmd == 'uname -s') return 'Linux';
            if (cmd.contains('os-release')) return 'ID=ubuntu';
            return '';
          },
          shouldThrow: (cmd) => cmd == 'tmux -V',
        );

        final result = await service.checkTmux();
        expect(result.isInstalled, isFalse);
        expect(result.version, isNull);
        expect(result.osType, RemoteOsType.debian);
      });

      test('returns not installed when tmux -V returns empty', () async {
        mockSsh.onExecute((cmd) {
          if (cmd == 'tmux -V') return '';
          if (cmd == 'uname -s') return 'Linux';
          if (cmd.contains('os-release')) return 'ID=ubuntu';
          return '';
        });

        final result = await service.checkTmux();
        expect(result.isInstalled, isFalse);
      });
    });

    group('detectOsType', () {
      test('detects macOS', () async {
        mockSsh.onExecute((cmd) {
          if (cmd == 'uname -s') return 'Darwin';
          return '';
        });

        final osType = await service.detectOsType();
        expect(osType, RemoteOsType.macos);
      });

      test('detects Debian/Ubuntu', () async {
        mockSsh.onExecute((cmd) {
          if (cmd == 'uname -s') return 'Linux';
          if (cmd.contains('os-release')) {
            return 'ID=ubuntu\nVERSION_ID="22.04"';
          }
          return '';
        });

        final osType = await service.detectOsType();
        expect(osType, RemoteOsType.debian);
      });

      test('detects RHEL/CentOS', () async {
        mockSsh.onExecute((cmd) {
          if (cmd == 'uname -s') return 'Linux';
          if (cmd.contains('os-release')) {
            return 'ID="centos"\nVERSION_ID="8"';
          }
          return '';
        });

        final osType = await service.detectOsType();
        expect(osType, RemoteOsType.redhat);
      });

      test('detects Fedora', () async {
        mockSsh.onExecute((cmd) {
          if (cmd == 'uname -s') return 'Linux';
          if (cmd.contains('os-release')) {
            return 'ID=fedora\nVERSION_ID=39';
          }
          return '';
        });

        final osType = await service.detectOsType();
        expect(osType, RemoteOsType.redhat);
      });

      test('detects Alpine', () async {
        mockSsh.onExecute((cmd) {
          if (cmd == 'uname -s') return 'Linux';
          if (cmd.contains('os-release')) {
            return 'ID=alpine\nVERSION_ID=3.19';
          }
          return '';
        });

        final osType = await service.detectOsType();
        expect(osType, RemoteOsType.alpine);
      });

      test('falls back to package manager detection', () async {
        mockSsh.onExecuteWithErrors(
          handler: (cmd) {
            if (cmd == 'uname -s') return 'Linux';
            if (cmd.contains('which apt-get')) return '/usr/bin/apt-get';
            return '';
          },
          shouldThrow: (cmd) => cmd.contains('os-release'),
        );

        final osType = await service.detectOsType();
        expect(osType, RemoteOsType.debian);
      });

      test('returns unknown for unrecognized OS', () async {
        mockSsh.onExecuteWithErrors(
          handler: (cmd) {
            if (cmd == 'uname -s') return 'SomeOS';
            return '';
          },
          shouldThrow: (cmd) => false,
        );

        final osType = await service.detectOsType();
        expect(osType, RemoteOsType.unknown);
      });
    });

    group('getInstallCommand', () {
      test('returns apt command for Debian', () {
        final cmd = TmuxInstallService.getInstallCommand(RemoteOsType.debian);
        expect(cmd, contains('apt-get'));
        expect(cmd, contains('tmux'));
      });

      test('returns yum command for Red Hat', () {
        final cmd = TmuxInstallService.getInstallCommand(RemoteOsType.redhat);
        expect(cmd, contains('yum'));
        expect(cmd, contains('tmux'));
      });

      test('returns apk command for Alpine', () {
        final cmd = TmuxInstallService.getInstallCommand(RemoteOsType.alpine);
        expect(cmd, contains('apk'));
        expect(cmd, contains('tmux'));
      });

      test('returns brew command for macOS', () {
        final cmd = TmuxInstallService.getInstallCommand(RemoteOsType.macos);
        expect(cmd, contains('brew'));
        expect(cmd, contains('tmux'));
      });

      test('returns null for unknown OS', () {
        final cmd = TmuxInstallService.getInstallCommand(RemoteOsType.unknown);
        expect(cmd, isNull);
      });
    });

    group('getOsDisplayName', () {
      test('returns display names for all OS types', () {
        expect(
          TmuxInstallService.getOsDisplayName(RemoteOsType.debian),
          'Debian/Ubuntu',
        );
        expect(
          TmuxInstallService.getOsDisplayName(RemoteOsType.redhat),
          'RHEL/CentOS/Fedora',
        );
        expect(
          TmuxInstallService.getOsDisplayName(RemoteOsType.alpine),
          'Alpine Linux',
        );
        expect(
          TmuxInstallService.getOsDisplayName(RemoteOsType.macos),
          'macOS',
        );
        expect(
          TmuxInstallService.getOsDisplayName(RemoteOsType.unknown),
          'Unknown OS',
        );
      });
    });

    group('installTmux', () {
      test('executes install command and verifies success', () async {
        mockSsh.onExecute((cmd) {
          if (cmd.contains('apt-get')) return '';
          if (cmd == 'tmux -V') return 'tmux 3.4';
          return '';
        });

        final success = await service.installTmux(RemoteOsType.debian);
        expect(success, isTrue);
        expect(
          mockSsh.commands,
          contains('sudo apt-get update && sudo apt-get install -y tmux'),
        );
      });

      test('returns false when tmux still not available after install',
          () async {
        mockSsh.onExecuteWithErrors(
          handler: (cmd) {
            if (cmd.contains('apt-get')) return '';
            return '';
          },
          shouldThrow: (cmd) => cmd == 'tmux -V',
        );

        final success = await service.installTmux(RemoteOsType.debian);
        expect(success, isFalse);
      });

      test('throws TmuxInstallException for unknown OS', () async {
        expect(
          () => service.installTmux(RemoteOsType.unknown),
          throwsA(isA<TmuxInstallException>()),
        );
      });

      test('throws TmuxInstallException when install command fails', () async {
        mockSsh.onExecuteWithErrors(
          handler: (cmd) => '',
          shouldThrow: (cmd) => cmd.contains('apt-get'),
        );

        expect(
          () => service.installTmux(RemoteOsType.debian),
          throwsA(isA<TmuxInstallException>()),
        );
      });
    });

    group('TmuxCheckResult', () {
      test('stores installed status with version', () {
        const result = TmuxCheckResult(
          isInstalled: true,
          version: 'tmux 3.4',
          osType: RemoteOsType.debian,
        );
        expect(result.isInstalled, isTrue);
        expect(result.version, 'tmux 3.4');
        expect(result.osType, RemoteOsType.debian);
      });

      test('stores not-installed status without version', () {
        const result = TmuxCheckResult(
          isInstalled: false,
          osType: RemoteOsType.macos,
        );
        expect(result.isInstalled, isFalse);
        expect(result.version, isNull);
        expect(result.osType, RemoteOsType.macos);
      });
    });
  });
}
