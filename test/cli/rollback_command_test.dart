import 'package:test/test.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:flutterfix/flutterfix.dart';

void main() {
  late Logger logger;
  late RollbackCommand rollbackCommand;

  setUp(() {
    logger = Logger(level: Level.quiet);
  });

  group('RollbackCommand', () {
    test('should create command with default options', () {
      rollbackCommand = RollbackCommand(logger, '.');

      expect(rollbackCommand.projectPath, equals('.'));
      expect(rollbackCommand.listOnly, isFalse);
      expect(rollbackCommand.backupId, isNull);
      expect(rollbackCommand.latest, isFalse);
      expect(rollbackCommand.clearAll, isFalse);
    });

    test('should create command with listOnly flag', () {
      rollbackCommand = RollbackCommand(
        logger,
        '.',
        listOnly: true,
      );

      expect(rollbackCommand.listOnly, isTrue);
    });

    test('should create command with backupId', () {
      rollbackCommand = RollbackCommand(
        logger,
        '.',
        backupId: '123456',
      );

      expect(rollbackCommand.backupId, equals('123456'));
    });

    test('should create command with latest flag', () {
      rollbackCommand = RollbackCommand(
        logger,
        '.',
        latest: true,
      );

      expect(rollbackCommand.latest, isTrue);
    });

    test('should create command with clearAll flag', () {
      rollbackCommand = RollbackCommand(
        logger,
        '.',
        clearAll: true,
      );

      expect(rollbackCommand.clearAll, isTrue);
    });
  });
}
