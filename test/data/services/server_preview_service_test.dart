import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/services/server_preview_service.dart';

void main() {
  group('ServerPreviewService', () {
    group('parseOsRelease', () {
      test('extracts PRETTY_NAME with double quotes', () {
        const input = '''
NAME="Ubuntu"
VERSION="22.04.3 LTS (Jammy Jellyfish)"
PRETTY_NAME="Ubuntu 22.04.3 LTS"
VERSION_ID="22.04"
''';
        expect(
          ServerPreviewService.parseOsRelease(input),
          'Ubuntu 22.04.3 LTS',
        );
      });

      test('extracts PRETTY_NAME without quotes', () {
        const input = '''
PRETTY_NAME=Alpine Linux v3.18
''';
        expect(
          ServerPreviewService.parseOsRelease(input),
          'Alpine Linux v3.18',
        );
      });

      test('returns null for empty content', () {
        expect(ServerPreviewService.parseOsRelease(''), isNull);
      });

      test('returns null when PRETTY_NAME is missing', () {
        const input = '''
NAME="Debian GNU/Linux"
VERSION_ID="12"
''';
        expect(ServerPreviewService.parseOsRelease(input), isNull);
      });

      test('returns null for empty PRETTY_NAME value', () {
        const input = 'PRETTY_NAME=""';
        expect(ServerPreviewService.parseOsRelease(input), isNull);
      });
    });

    group('parseUptime', () {
      test('parses standard uptime with days', () {
        const input =
            ' 14:22:01 up 14 days,  3:22,  2 users,  load average: 0.00, 0.01, 0.05';
        expect(
          ServerPreviewService.parseUptime(input),
          'up 14 days, 3:22',
        );
      });

      test('parses uptime with hours only', () {
        const input =
            ' 10:30:00 up  5:42,  1 user,  load average: 0.10, 0.05, 0.01';
        expect(
          ServerPreviewService.parseUptime(input),
          'up 5:42',
        );
      });

      test('parses uptime with minutes only', () {
        const input =
            ' 09:00:00 up 12 min,  1 user,  load average: 0.00, 0.01, 0.00';
        expect(
          ServerPreviewService.parseUptime(input),
          'up 12 min',
        );
      });

      test('returns null for empty input', () {
        expect(ServerPreviewService.parseUptime(''), isNull);
      });
    });

    group('parseMemory', () {
      test('parses standard free -h output', () {
        const input = '''
               total        used        free      shared  buff/cache   available
Mem:           7.7Gi       3.8Gi       1.2Gi       256Mi       2.7Gi       3.5Gi
Swap:          2.0Gi          0B       2.0Gi
''';
        expect(
          ServerPreviewService.parseMemory(input),
          '3.8Gi / 7.7Gi',
        );
      });

      test('parses minimal free output', () {
        const input = '''
              total        used        free
Mem:          512Mi       128Mi       384Mi
''';
        expect(
          ServerPreviewService.parseMemory(input),
          '128Mi / 512Mi',
        );
      });

      test('returns null for empty input', () {
        expect(ServerPreviewService.parseMemory(''), isNull);
      });

      test('returns null when Mem line is missing', () {
        const input = 'Swap:  2.0Gi  0B  2.0Gi';
        expect(ServerPreviewService.parseMemory(input), isNull);
      });
    });

    group('parseDisk', () {
      test('parses standard df -h output', () {
        const input = '''
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       100G   42G   53G  45% /
''';
        expect(
          ServerPreviewService.parseDisk(input),
          '42G / 100G (45%)',
        );
      });

      test('skips header line and finds data', () {
        const input = '''
Filesystem      Size  Used Avail Use% Mounted on
overlay          50G   20G   28G  42% /
''';
        expect(
          ServerPreviewService.parseDisk(input),
          '20G / 50G (42%)',
        );
      });

      test('returns null for empty input', () {
        expect(ServerPreviewService.parseDisk(''), isNull);
      });

      test('returns null for header-only input', () {
        const input = 'Filesystem      Size  Used Avail Use% Mounted on';
        expect(ServerPreviewService.parseDisk(input), isNull);
      });
    });
  });
}
