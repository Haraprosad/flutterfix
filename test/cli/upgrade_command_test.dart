import 'package:test/test.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:flutterfix/src/cli/upgrade_command.dart';

void main() {
  group('UpgradeCommand', () {
    test('execute completes without error', () async {
      final logger = Logger(level: Level.quiet);
      final command = UpgradeCommand(logger);

      await command.execute();
      expect(true, isTrue);
    });
  });
}
