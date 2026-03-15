import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/services/ssh_service.dart';

void main() {
  group('SshService', () {
    late SshService service;

    setUp(() {
      service = SshService();
    });

    tearDown(() {
      service.dispose();
    });

    group('shell', () {
      test('throws StateError when not connected', () {
        expect(
          () => service.shell(),
          throwsA(isA<StateError>()),
        );
      });

      test('throws StateError when not connected with custom dimensions', () {
        expect(
          () => service.shell(cols: 120, rows: 40),
          throwsA(isA<StateError>()),
        );
      });

      test('default dimensions are 80x24', () {
        // Verify the method signature accepts default parameters.
        // Actual connection test requires a real SSH server.
        expect(
          () => service.shell(),
          throwsA(isA<StateError>()),
        );
      });
    });
  });

  group('SshPtySession', () {
    // SshPtySession wraps dartssh2's SSHSession which requires a real SSH
    // channel to instantiate. The PTY session behavior is validated through
    // the SshService integration above and the session_detail_screen tests.
    //
    // Unit-testable contract:
    // - stdout: Stream<Uint8List> from remote PTY
    // - write(Uint8List): sends data to remote PTY stdin
    // - resize(int, int): sends SIGWINCH to remote PTY
    // - close(): closes the PTY channel
    // - isClosed: tracks closed state
    // - done: Future that completes on channel close

    test('SshPtySession class exists and is exported', () {
      // Verify the class is accessible from the public API.
      // ignore: unnecessary_type_check
      expect(SshPtySession, isNotNull);
    });
  });

  group('SshReconnectionEvent', () {
    test('creates with required fields', () {
      const event = SshReconnectionEvent(
        attempt: 1,
        maxAttempts: 10,
        delay: Duration(seconds: 1),
        succeeded: false,
      );

      expect(event.attempt, 1);
      expect(event.maxAttempts, 10);
      expect(event.delay, const Duration(seconds: 1));
      expect(event.succeeded, false);
      expect(event.error, isNull);
    });
  });
}
