/// Analyzes terminal output to extract structured error information.
///
/// Supports common build tools and package managers by matching known error
/// patterns and producing an [ErrorAnalysis] with the error message, likely
/// cause, suggested fix, and any file paths referenced in the output.
class ErrorAnalyzer {
  /// Compiled error patterns keyed by tool/ecosystem name.
  ///
  /// Each entry maps a descriptive key to a [_ErrorPattern] containing a
  /// regex, a cause template, and a suggestion template.
  static final List<_ErrorPattern> _patterns = [
    // npm / Node.js
    _ErrorPattern(
      regex: RegExp(
        r'npm ERR! .*|Error: Cannot find module',
        multiLine: true,
      ),
      ecosystem: 'npm',
      causeTemplate: 'Node.js dependency or module resolution failure.',
      suggestionTemplate:
          'Run "npm install" to restore missing dependencies. '
          'Check that the module name and version are correct in package.json.',
    ),

    // pip / Python
    _ErrorPattern(
      regex: RegExp(
        r'ERROR: .*(?:No matching distribution|Could not install|pip install)|'
        r'ModuleNotFoundError: No module named',
        multiLine: true,
      ),
      ecosystem: 'pip',
      causeTemplate: 'Python package installation or import failure.',
      suggestionTemplate:
          'Verify the package name and Python version compatibility. '
          'Try "pip install --upgrade <package>" or check your virtual environment.',
    ),

    // cargo / Rust
    _ErrorPattern(
      regex: RegExp(
        r'error\[E\d+\]:.*|cargo build.*failed',
        multiLine: true,
      ),
      ecosystem: 'cargo',
      causeTemplate: 'Rust compilation error.',
      suggestionTemplate:
          'Read the compiler error message carefully — Rust errors are '
          'usually descriptive. Run "cargo check" for a faster feedback loop.',
    ),

    // Flutter / Dart
    _ErrorPattern(
      regex: RegExp(
        r'Error: .*lib/.*\.dart:\d+:\d+|'
        r'flutter: .*Error|'
        r'Could not find.*pubspec\.yaml|'
        r'\[ERROR:flutter/.*\]',
        multiLine: true,
      ),
      ecosystem: 'flutter',
      causeTemplate: 'Flutter/Dart build or runtime error.',
      suggestionTemplate:
          'Run "flutter pub get" to sync dependencies. '
          'Check the referenced file and line number for syntax or type errors.',
    ),

    // Go
    _ErrorPattern(
      regex: RegExp(
        r'\.go:\d+:\d+:.*|cannot find package|go build.*failed',
        multiLine: true,
      ),
      ecosystem: 'go',
      causeTemplate: 'Go compilation or package resolution error.',
      suggestionTemplate:
          'Run "go mod tidy" to fix dependency issues. '
          'Check the file and line number referenced in the error.',
    ),

    // Java / Gradle / Maven
    _ErrorPattern(
      regex: RegExp(
        r'BUILD FAILED|'
        r'error: .*\.java:\d+|'
        r'COMPILATION ERROR|'
        r'Could not resolve.*dependencies',
        multiLine: true,
      ),
      ecosystem: 'java',
      causeTemplate: 'Java build or dependency resolution failure.',
      suggestionTemplate:
          'Check the build tool output for the root cause. '
          'Run "gradle build --info" or "mvn -X" for verbose diagnostics.',
    ),

    // Generic compilation / permission / command not found
    _ErrorPattern(
      regex: RegExp(
        r'Permission denied|command not found|No such file or directory',
        multiLine: true,
      ),
      ecosystem: 'shell',
      causeTemplate: 'Shell environment or filesystem error.',
      suggestionTemplate:
          'Check file permissions, verify the command is installed, '
          'and ensure the file path is correct.',
    ),

    // Generic error fallback (broad match — must be last)
    _ErrorPattern(
      regex: RegExp(
        r'(?:^|\n)(?:error|Error|ERROR)[:\s].*',
        multiLine: true,
      ),
      ecosystem: 'generic',
      causeTemplate: 'An error was detected in the terminal output.',
      suggestionTemplate:
          'Review the full error message above for specifics. '
          'Check logs or run the command with verbose/debug flags for more info.',
    ),
  ];

  /// File path extraction pattern.
  ///
  /// Matches common path formats: absolute paths, relative paths with
  /// extensions, and paths with line:column suffixes.
  static final RegExp _filePathPattern = RegExp(
    r'(?:^|[\s:])(/[\w./-]+\.\w+|[\w./-]+\.(?:dart|js|ts|py|rs|go|java|kt|rb|swift|c|cpp|h|hpp))'
    r'(?::(\d+)(?::(\d+))?)?',
    multiLine: true,
  );

  const ErrorAnalyzer();

  /// Analyze terminal [output] and return structured error information.
  ///
  /// Returns `null` if no error pattern matches the output. When a match
  /// is found, extracts the error message, determines the likely cause,
  /// suggests a fix, and lists any file paths mentioned in the output.
  ErrorAnalysis? analyzeError(String output) {
    if (output.isEmpty) return null;

    for (final pattern in _patterns) {
      final match = pattern.regex.firstMatch(output);
      if (match == null) continue;

      final message = _extractErrorMessage(output, match);
      final files = _extractFilePaths(output);

      return ErrorAnalysis(
        message: message,
        cause: pattern.causeTemplate,
        suggestion: pattern.suggestionTemplate,
        files: files,
        ecosystem: pattern.ecosystem,
      );
    }

    return null;
  }

  /// Extract the most relevant error message from the output around the
  /// matched region, including up to 2 surrounding lines for context.
  String _extractErrorMessage(String output, RegExpMatch match) {
    final lines = output.split('\n');
    final matchLine = output.substring(0, match.start).split('\n').length - 1;

    final start = (matchLine - 1).clamp(0, lines.length - 1);
    final end = (matchLine + 2).clamp(0, lines.length);

    return lines
        .sublist(start, end)
        .where((line) => line.trim().isNotEmpty)
        .join('\n')
        .trim();
  }

  /// Extract all file paths mentioned in the terminal output.
  List<String> _extractFilePaths(String output) {
    final matches = _filePathPattern.allMatches(output);
    final paths = <String>{};

    for (final match in matches) {
      final path = match.group(1);
      if (path == null) continue;

      final lineNum = match.group(2);
      final colNum = match.group(3);

      var reference = path;
      if (lineNum != null) {
        reference += ':$lineNum';
        if (colNum != null) {
          reference += ':$colNum';
        }
      }
      paths.add(reference);
    }

    return paths.toList();
  }
}

/// Structured result of error analysis.
///
/// Contains the extracted error message, likely cause, a suggested fix,
/// and any file paths referenced in the terminal output.
class ErrorAnalysis {
  /// The extracted error message from the terminal output.
  final String message;

  /// A human-readable description of the likely cause.
  final String cause;

  /// A suggested fix or next step to resolve the error.
  final String suggestion;

  /// File paths (with optional line:column suffixes) found in the output.
  final List<String> files;

  /// The detected ecosystem/tool (e.g. "npm", "flutter", "cargo").
  final String ecosystem;

  const ErrorAnalysis({
    required this.message,
    required this.cause,
    required this.suggestion,
    required this.files,
    required this.ecosystem,
  });

  /// Format the analysis as a structured summary string suitable for
  /// voice readback or logging.
  String toSummary() {
    final buffer = StringBuffer();
    buffer.writeln('Error Message: $message');
    buffer.writeln('Likely Cause: $cause');
    buffer.writeln('Suggested Fix: $suggestion');
    if (files.isNotEmpty) {
      buffer.writeln('Relevant Files: ${files.join(', ')}');
    }
    return buffer.toString().trim();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorAnalysis &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          cause == other.cause &&
          suggestion == other.suggestion &&
          ecosystem == other.ecosystem;

  @override
  int get hashCode => Object.hash(message, cause, suggestion, ecosystem);

  @override
  String toString() =>
      'ErrorAnalysis(ecosystem: $ecosystem, message: "$message", '
      'files: $files)';
}

/// Internal pattern definition for error matching.
class _ErrorPattern {
  final RegExp regex;
  final String ecosystem;
  final String causeTemplate;
  final String suggestionTemplate;

  const _ErrorPattern({
    required this.regex,
    required this.ecosystem,
    required this.causeTemplate,
    required this.suggestionTemplate,
  });
}
