import 'package:test/test.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:flutterfix/src/resolver/dependency_resolver.dart';

void main() {
  group('DependencyResolver', () {
    late Logger logger;
    late DependencyResolver resolver;

    setUp(() {
      logger = Logger(level: Level.quiet);
      resolver = DependencyResolver(logger, '.');
    });

    test('constructs with logger and project path', () {
      expect(resolver, isNotNull);
      expect(resolver, isA<DependencyResolver>());
    });

    test('getDartSdkVersion returns version string', () async {
      final version = await resolver.getDartSdkVersion();
      // Version can be null if dart is not in PATH, or a string like "3.5.4"
      expect(version, anyOf(isNull, matches(RegExp(r'^\d+\.\d+\.\d+'))));
    });
  });

  group('PubGetResult', () {
    test('hasConflicts returns true when conflicts exist', () {
      final result = PubGetResult(
        success: false,
        output: 'error output',
        conflicts: [
          DependencyConflict(
            package: 'test_package',
            currentVersion: '1.0.0',
            conflictingDependency: 'other_package',
            requiredVersion: '2.0.0',
          ),
        ],
      );

      expect(result.hasConflicts, isTrue);
      expect(result.success, isFalse);
    });

    test('hasConflicts returns false when no conflicts', () {
      final result = PubGetResult(
        success: true,
        output: 'success',
        conflicts: [],
      );

      expect(result.hasConflicts, isFalse);
      expect(result.success, isTrue);
    });
  });

  group('DependencyConflict', () {
    test('creates conflict with all required fields', () {
      final conflict = DependencyConflict(
        package: 'http_parser',
        currentVersion: '4.1.2',
        conflictingDependency: 'collection',
        requiredVersion: '^1.19.0',
      );

      expect(conflict.package, equals('http_parser'));
      expect(conflict.currentVersion, equals('4.1.2'));
      expect(conflict.conflictingDependency, equals('collection'));
      expect(conflict.requiredVersion, equals('^1.19.0'));
    });

    test('toString provides readable conflict description', () {
      final conflict = DependencyConflict(
        package: 'http_parser',
        currentVersion: '4.1.2',
        conflictingDependency: 'collection',
        requiredVersion: '^1.19.0',
      );

      final description = conflict.toString();
      expect(description, contains('http_parser'));
      expect(description, contains('4.1.2'));
      expect(description, contains('collection'));
      expect(description, contains('^1.19.0'));
      expect(description, contains('conflicts with'));
    });
  });
}
