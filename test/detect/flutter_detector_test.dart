import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flutterfix/src/detect/flutter_detector.dart';

void main() {
  group('FlutterDetector', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flutterfix_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('detectInstalled returns FlutterInfo', () async {
      final info = await FlutterDetector.detectInstalled();
      expect(info, isA<FlutterInfo>());
    });

    test('detectFromProject reads pubspec.yaml', () async {
      await File(p.join(tempDir.path, 'pubspec.yaml')).writeAsString('''
name: test_app
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
''');

      final info = await FlutterDetector.detectFromProject(tempDir.path);
      expect(info.projectName, equals('test_app'));
      expect(info.sdkConstraint, equals('>=3.0.0 <4.0.0'));
    });

    test('FlutterInfo majorMinorVersion extracts version correctly', () {
      final info = FlutterInfo(version: '3.24.5', isInstalled: true);
      expect(info.majorMinorVersion, equals('3.24'));
    });
  });
}
