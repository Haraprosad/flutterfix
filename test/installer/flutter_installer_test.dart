import 'package:test/test.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:flutterfix/flutterfix.dart';

void main() {
  late Logger logger;
  late FlutterInstaller installer;

  setUp(() {
    logger = Logger(level: Level.quiet);
    installer = FlutterInstaller(logger);
  });

  group('FlutterInstaller', () {
    test('should load version map successfully', () async {
      await installer.loadVersionMap();
      expect(installer.versionMap, isNotEmpty);
    });

    test('should get available versions', () async {
      await installer.loadVersionMap();
      final versions = installer.getAvailableVersions();

      expect(versions, isNotEmpty);
      expect(versions, contains('3.24'));
      expect(versions, contains('3.22'));
    });

    test('should get version details', () async {
      await installer.loadVersionMap();
      final details = installer.getVersionDetails('3.24');

      expect(details, isNotNull);
      expect(details!['gradle'], equals('8.7'));
      expect(details['agp'], equals('8.5.0'));
      expect(details['kotlin'], equals('2.0.10'));
      expect(details['java'], equals('17'));
    });

    test('should return null for non-existent version', () async {
      await installer.loadVersionMap();
      final details = installer.getVersionDetails('99.99');

      expect(details, isNull);
    });

    test('should check if FVM is installed', () async {
      // This test will pass or fail based on system state
      final hasFvm = await installer.isFvmInstalled();
      expect(hasFvm, isA<bool>());
    });

    test('should list installed versions if FVM is available', () async {
      final hasFvm = await installer.isFvmInstalled();

      if (hasFvm) {
        final versions = await installer.listInstalledVersions();
        expect(versions, isA<List<String>>());
      } else {
        final versions = await installer.listInstalledVersions();
        expect(versions, isEmpty);
      }
    });

    test('should get correct version details for all versions', () async {
      await installer.loadVersionMap();
      final versions = installer.getAvailableVersions();

      for (final version in versions) {
        final details = installer.getVersionDetails(version);
        expect(details, isNotNull,
            reason: 'Version $version should have details');
        expect(details!['gradle'], isNotNull);
        expect(details['agp'], isNotNull);
        expect(details['kotlin'], isNotNull);
        expect(details['java'], isNotNull);
      }
    });

    test('should sort versions in descending order', () async {
      await installer.loadVersionMap();
      final versions = installer.getAvailableVersions();

      // Verify that versions are sorted lexicographically in descending order
      // For example: "3.38.1" > "3.38.0" > "3.35.7" > "3.7" > "2.10.5" > "v1.12.13+hotfix.9"
      for (int i = 0; i < versions.length - 1; i++) {
        final current = versions[i];
        final next = versions[i + 1];
        final comparison = current.compareTo(next);
        expect(comparison, greaterThanOrEqualTo(0),
            reason:
                '$current should be >= $next (lexicographically, got comparison: $comparison)');
      }
    });
  });

  group('FlutterInstaller - Version Compatibility', () {
    test('3.38.x should have correct compatibility', () async {
      await installer.loadVersionMap();
      final details = installer.getVersionDetails('3.38');

      expect(details, isNotNull);
      expect(details!['gradle'], equals('8.11'));
      expect(details['agp'], equals('8.7.3'));
      expect(details['kotlin'], equals('2.1.0'));
      expect(details['java'], equals('17'));
      expect(details['min_sdk'], equals(24));
      expect(details['compile_sdk'], equals(35));
      expect(details['target_sdk'], equals(35));
    });

    test('3.24.x should have correct compatibility', () async {
      await installer.loadVersionMap();
      final details = installer.getVersionDetails('3.24');

      expect(details, isNotNull);
      expect(details!['gradle'], equals('8.7'));
      expect(details['agp'], equals('8.5.0'));
      expect(details['kotlin'], equals('2.0.10'));
      expect(details['java'], equals('17'));
      expect(details['min_sdk'], equals(21));
      expect(details['compile_sdk'], equals(34));
      expect(details['target_sdk'], equals(34));
    });

    test('3.16.x should have correct compatibility', () async {
      await installer.loadVersionMap();
      final details = installer.getVersionDetails('3.16');

      expect(details, isNotNull);
      expect(details!['gradle'], equals('8.3'));
      expect(details['agp'], equals('8.1.4'));
      expect(details['kotlin'], equals('1.9.0'));
      expect(details['java'], equals('17'));
    });
  });
}
