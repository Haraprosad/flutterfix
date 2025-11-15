import 'package:test/test.dart';
import 'package:flutterfix/src/runner/process_runner.dart';

void main() {
  group('ProcessRunner', () {
    test('run executes command successfully', () async {
      final result = await ProcessRunner.run('echo', ['hello']);
      expect(result.success, isTrue);
      expect(result.stdout, contains('hello'));
    });

    test('commandExists returns true for existing command', () async {
      final exists = await ProcessRunner.commandExists('echo');
      expect(exists, isTrue);
    });

    test('commandExists returns false for non-existing command', () async {
      final exists = await ProcessRunner.commandExists('nonexistent_cmd_xyz');
      expect(exists, isFalse);
    });

    test('dart command executes', () async {
      final result = await ProcessRunner.dart(['--version']);
      expect(result, isNotNull);
    });
  });
}
