import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flutterfix/src/patcher/kotlin_patcher.dart';

void main() {
  group('KotlinPatcher', () {
    late Directory tempDir;
    late KotlinPatcher patcher;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flutterfix_test_');
      patcher = KotlinPatcher(tempDir.path);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('updateVersion updates kotlin version', () async {
      final androidDir = Directory(p.join(tempDir.path, 'android'));
      await androidDir.create();

      final buildFile = File(p.join(androidDir.path, 'build.gradle'));
      await buildFile.writeAsString('''
buildscript {
    ext.kotlin_version = '1.7.10'
}
''');

      final result = await patcher.updateVersion('1.9.0');
      expect(result, isTrue);

      final content = await buildFile.readAsString();
      expect(content, contains("ext.kotlin_version = '1.9.0'"));
    });
  });
}
