import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flutterfix/src/patcher/agp_patcher.dart';

void main() {
  group('AgpPatcher', () {
    late Directory tempDir;
    late AgpPatcher patcher;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flutterfix_test_');
      patcher = AgpPatcher(tempDir.path);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('updateSdkVersions updates min, compile, and target SDK', () async {
      final appDir = Directory(p.join(tempDir.path, 'android', 'app'));
      await appDir.create(recursive: true);

      final buildFile = File(p.join(appDir.path, 'build.gradle'));
      await buildFile.writeAsString('''
android {
    compileSdk 33
    defaultConfig {
        minSdkVersion 19
        targetSdkVersion 33
    }
}
''');

      final result = await patcher.updateSdkVersions(
        minSdk: 21,
        compileSdk: 34,
        targetSdk: 34,
      );
      expect(result, isTrue);

      final content = await buildFile.readAsString();
      expect(content, contains('minSdkVersion 21'));
      expect(content, contains('targetSdkVersion 34'));
    });
  });
}
