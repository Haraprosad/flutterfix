import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flutterfix/src/detect/gradle_detector.dart';

void main() {
  group('GradleDetector', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flutterfix_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('detectWrapperVersion extracts version from properties', () async {
      final wrapperDir =
          Directory(p.join(tempDir.path, 'android', 'gradle', 'wrapper'));
      await wrapperDir.create(recursive: true);

      await File(p.join(wrapperDir.path, 'gradle-wrapper.properties'))
          .writeAsString('''
distributionUrl=https\\://services.gradle.org/distributions/gradle-8.3-bin.zip
''');

      final version = await GradleDetector.detectWrapperVersion(tempDir.path);
      expect(version, equals('8.3'));
    });

    test('isCompatibleWithJava checks Gradle 8.0+ requires Java 17+', () {
      expect(GradleDetector.isCompatibleWithJava('8.0', '17'), isTrue);
      expect(GradleDetector.isCompatibleWithJava('8.0', '11'), isFalse);
    });

    test('isCompatibleWithJava checks Gradle 7.0+ requires Java 11+', () {
      expect(GradleDetector.isCompatibleWithJava('7.0', '11'), isTrue);
      expect(GradleDetector.isCompatibleWithJava('7.0', '8'), isFalse);
    });
  });
}
