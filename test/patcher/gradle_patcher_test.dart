import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flutterfix/src/patcher/gradle_patcher.dart';

void main() {
  group('GradlePatcher', () {
    late Directory tempDir;
    late GradlePatcher patcher;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flutterfix_test_');
      patcher = GradlePatcher(tempDir.path);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('updateWrapperVersion updates gradle version', () async {
      final wrapperDir =
          Directory(p.join(tempDir.path, 'android', 'gradle', 'wrapper'));
      await wrapperDir.create(recursive: true);

      final propsFile =
          File(p.join(wrapperDir.path, 'gradle-wrapper.properties'));
      await propsFile.writeAsString(
          'distributionUrl=https\\://services.gradle.org/distributions/gradle-7.5-bin.zip');

      final result = await patcher.updateWrapperVersion('8.3');
      expect(result, isTrue);

      final content = await propsFile.readAsString();
      expect(content, contains('gradle-8.3-bin.zip'));
    });

    test('optimizeProperties creates gradle.properties with optimizations',
        () async {
      final androidDir = Directory(p.join(tempDir.path, 'android'));
      await androidDir.create();

      final result = await patcher.optimizeProperties();
      expect(result, isTrue);

      final propsFile = File(p.join(androidDir.path, 'gradle.properties'));
      final content = await propsFile.readAsString();
      expect(content, contains('org.gradle.parallel=true'));
    });
  });
}
