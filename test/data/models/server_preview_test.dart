import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/server_preview.dart';

void main() {
  group('ServerPreview', () {
    group('hasData', () {
      test('returns false when all fields are null', () {
        final preview = ServerPreview(fetchedAt: DateTime(2025, 1, 1));
        expect(preview.hasData, false);
      });

      test('returns true when motd is set', () {
        final preview = ServerPreview(
          motd: 'Welcome',
          fetchedAt: DateTime(2025, 1, 1),
        );
        expect(preview.hasData, true);
      });

      test('returns true when osName is set', () {
        final preview = ServerPreview(
          osName: 'Ubuntu 22.04',
          fetchedAt: DateTime(2025, 1, 1),
        );
        expect(preview.hasData, true);
      });

      test('returns true when uptime is set', () {
        final preview = ServerPreview(
          uptime: 'up 14 days',
          fetchedAt: DateTime(2025, 1, 1),
        );
        expect(preview.hasData, true);
      });

      test('returns true when memory is set', () {
        final preview = ServerPreview(
          memory: '3.8Gi / 7.7Gi',
          fetchedAt: DateTime(2025, 1, 1),
        );
        expect(preview.hasData, true);
      });

      test('returns true when disk is set', () {
        final preview = ServerPreview(
          disk: '42G / 100G (45%)',
          fetchedAt: DateTime(2025, 1, 1),
        );
        expect(preview.hasData, true);
      });
    });

    group('displayOs', () {
      test('prefers osName over uname', () {
        final preview = ServerPreview(
          osName: 'Ubuntu 22.04',
          uname: 'Linux server 5.15.0',
          fetchedAt: DateTime(2025, 1, 1),
        );
        expect(preview.displayOs, 'Ubuntu 22.04');
      });

      test('falls back to uname when osName is null', () {
        final preview = ServerPreview(
          uname: 'Linux server 5.15.0',
          fetchedAt: DateTime(2025, 1, 1),
        );
        expect(preview.displayOs, 'Linux server 5.15.0');
      });

      test('returns null when both are null', () {
        final preview = ServerPreview(fetchedAt: DateTime(2025, 1, 1));
        expect(preview.displayOs, isNull);
      });
    });

    group('summary', () {
      test('joins all available parts', () {
        final preview = ServerPreview(
          osName: 'Ubuntu 22.04',
          uptime: 'up 14 days',
          memory: '3.8Gi / 7.7Gi',
          fetchedAt: DateTime(2025, 1, 1),
        );
        expect(
          preview.summary,
          'Ubuntu 22.04  ·  up 14 days  ·  3.8Gi / 7.7Gi',
        );
      });

      test('omits null parts', () {
        final preview = ServerPreview(
          osName: 'Alpine Linux',
          fetchedAt: DateTime(2025, 1, 1),
        );
        expect(preview.summary, 'Alpine Linux');
      });

      test('returns empty string when no parts available', () {
        final preview = ServerPreview(fetchedAt: DateTime(2025, 1, 1));
        expect(preview.summary, '');
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final original = ServerPreview(
          osName: 'Ubuntu 22.04',
          uptime: 'up 14 days',
          fetchedAt: DateTime(2025, 1, 1),
        );

        final updated = original.copyWith(
          uptime: 'up 15 days',
          memory: '4.0Gi / 7.7Gi',
        );

        expect(updated.osName, 'Ubuntu 22.04');
        expect(updated.uptime, 'up 15 days');
        expect(updated.memory, '4.0Gi / 7.7Gi');
        expect(updated.fetchedAt, DateTime(2025, 1, 1));
      });

      test('preserves unchanged fields', () {
        final original = ServerPreview(
          motd: 'Welcome',
          osName: 'Debian 12',
          uname: 'Linux host 6.1.0',
          uptime: 'up 3 days',
          memory: '2Gi / 4Gi',
          disk: '20G / 50G (40%)',
          fetchedAt: DateTime(2025, 6, 1),
        );

        final copy = original.copyWith();

        expect(copy.motd, original.motd);
        expect(copy.osName, original.osName);
        expect(copy.uname, original.uname);
        expect(copy.uptime, original.uptime);
        expect(copy.memory, original.memory);
        expect(copy.disk, original.disk);
        expect(copy.fetchedAt, original.fetchedAt);
      });
    });
  });
}
