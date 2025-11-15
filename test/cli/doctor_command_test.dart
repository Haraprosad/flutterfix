import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:mason_logger/mason_logger.dart';
import 'package:flutterfix/src/cli/doctor_command.dart';

void main() {
  group('DoctorCommand', () {
    late Directory tempDir;
    late Logger logger;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flutterfix_test_');
      logger = Logger(level: Level.quiet);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('execute handles non-Flutter project', () async {
      final command = DoctorCommand(logger, tempDir.path);
      await command.execute();
      expect(true, isTrue); // Should complete without error
    });

    test('execute handles valid Flutter project', () async {
      await File(p.join(tempDir.path, 'pubspec.yaml'))
          .writeAsString('name: test');
      await Directory(p.join(tempDir.path, 'lib')).create();

      final command = DoctorCommand(logger, tempDir.path);
      await command.execute();
      expect(true, isTrue);
    });
  });
}
