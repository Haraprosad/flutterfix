import 'package:test/test.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:flutterfix/flutterfix.dart';

void main() {
  late Logger logger;
  late InstallCommand installCommand;

  setUp(() {
    logger = Logger(level: Level.quiet);
  });

  group('InstallCommand', () {
    test('should create command with default options', () {
      installCommand = InstallCommand(logger, '.');

      expect(installCommand.projectPath, equals('.'));
      expect(installCommand.specificVersion, isNull);
      expect(installCommand.listVersions, isFalse);
      expect(installCommand.showInfo, isFalse);
      expect(installCommand.useFvm, isTrue);
    });

    test('should create command with specific version', () {
      installCommand = InstallCommand(
        logger,
        '.',
        specificVersion: '3.24',
      );

      expect(installCommand.specificVersion, equals('3.24'));
    });

    test('should create command with list flag', () {
      installCommand = InstallCommand(
        logger,
        '.',
        listVersions: true,
      );

      expect(installCommand.listVersions, isTrue);
    });

    test('should create command with no-fvm option', () {
      installCommand = InstallCommand(
        logger,
        '.',
        useFvm: false,
      );

      expect(installCommand.useFvm, isFalse);
    });

    test('should create command with show info flag', () {
      installCommand = InstallCommand(
        logger,
        '.',
        specificVersion: '3.24',
        showInfo: true,
      );

      expect(installCommand.showInfo, isTrue);
      expect(installCommand.specificVersion, equals('3.24'));
    });
  });
}
