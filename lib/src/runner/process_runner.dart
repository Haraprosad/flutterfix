import 'dart:io';
import 'dart:async';

class ProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool success;

  ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  }) : success = exitCode == 0;

  @override
  String toString() => 'ProcessResult(exitCode: $exitCode, success: $success)';
}

class ProcessRunner {
  /// Run a command and return the result
  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
    Duration? timeout,
  }) async {
    try {
      final ioResult = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: runInShell,
      ).timeout(
        timeout ?? const Duration(hours: 2), // Default 2 hour timeout
        onTimeout: () {
          throw TimeoutException(
            'Process timed out after ${timeout?.inMinutes ?? 120} minutes',
          );
        },
      );

      return ProcessResult(
        exitCode: ioResult.exitCode,
        stdout: ioResult.stdout.toString().trim(),
        stderr: ioResult.stderr.toString().trim(),
      );
    } on TimeoutException catch (e) {
      return ProcessResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Timeout: ${e.message}',
      );
    } catch (e) {
      return ProcessResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Check if a command exists in PATH
  static Future<bool> commandExists(String command) async {
    final result = await run(
      Platform.isWindows ? 'where' : 'which',
      [command],
      runInShell: true,
    );
    return result.success;
  }

  /// Get command version
  static Future<String?> getVersion(
    String command,
    List<String> versionArgs,
  ) async {
    final result = await run(command, versionArgs);
    if (!result.success) return null;

    final output = result.stdout + result.stderr;
    return output.isNotEmpty ? output : null;
  }

  /// Run Flutter command
  static Future<ProcessResult> flutter(
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    return run('flutter', arguments, workingDirectory: workingDirectory);
  }

  /// Run Dart command
  static Future<ProcessResult> dart(
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    return run('dart', arguments, workingDirectory: workingDirectory);
  }

  /// Run Gradle command
  static Future<ProcessResult> gradle(
    List<String> arguments, {
    required String projectPath,
  }) async {
    final gradleWrapper = Platform.isWindows
        ? '$projectPath/android/gradlew.bat'
        : '$projectPath/android/gradlew';

    return run(
      gradleWrapper,
      arguments,
      workingDirectory: '$projectPath/android',
    );
  }

  /// Run Java command
  static Future<ProcessResult> java(
    List<String> arguments,
  ) async {
    return run('java', arguments);
  }

  /// Kill process by name (platform-specific)
  static Future<bool> killProcess(String processName) async {
    if (Platform.isWindows) {
      final result = await run('taskkill', ['/F', '/IM', processName]);
      return result.success;
    } else {
      final result = await run('pkill', ['-9', processName]);
      return result.success;
    }
  }

  /// Check if process is running
  static Future<bool> isProcessRunning(String processName) async {
    if (Platform.isWindows) {
      final result = await run('tasklist', []);
      return result.stdout.toLowerCase().contains(processName.toLowerCase());
    } else {
      final result = await run('pgrep', [processName]);
      return result.success;
    }
  }
}
