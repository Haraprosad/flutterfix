import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flutterfix/src/utils/file_utils.dart';

void main() {
  group('FileUtils', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flutterfix_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('fileExists returns true for existing file', () async {
      final file = File(p.join(tempDir.path, 'test.txt'));
      await file.writeAsString('content');
      expect(FileUtils.fileExists(file.path), isTrue);
    });

    test('fileExists returns false for non-existing file', () {
      expect(
          FileUtils.fileExists(p.join(tempDir.path, 'missing.txt')), isFalse);
    });

    test('dirExists returns true for existing directory', () async {
      final dir = Directory(p.join(tempDir.path, 'subdir'));
      await dir.create();
      expect(FileUtils.dirExists(dir.path), isTrue);
    });

    test('dirExists returns false for non-existing directory', () {
      expect(FileUtils.dirExists(p.join(tempDir.path, 'missing')), isFalse);
    });

    test('readFile returns file content', () async {
      final file = File(p.join(tempDir.path, 'test.txt'));
      await file.writeAsString('test content');
      final content = await FileUtils.readFile(file.path);
      expect(content, equals('test content'));
    });

    test('writeFile creates file with content', () async {
      final path = p.join(tempDir.path, 'new.txt');
      await FileUtils.writeFile(path, 'new content');
      final content = await File(path).readAsString();
      expect(content, equals('new content'));
    });

    test('replaceInFile replaces text', () async {
      final path = p.join(tempDir.path, 'test.txt');
      await File(path).writeAsString('Hello World');
      await FileUtils.replaceInFile(path, 'World', 'Dart');
      final content = await File(path).readAsString();
      expect(content, equals('Hello Dart'));
    });

    test('isFlutterProject returns true for valid project', () async {
      await File(p.join(tempDir.path, 'pubspec.yaml')).writeAsString('');
      await Directory(p.join(tempDir.path, 'lib')).create();
      expect(FileUtils.isFlutterProject(tempDir.path), isTrue);
    });

    test('isFlutterProject returns false when missing pubspec', () async {
      await Directory(p.join(tempDir.path, 'lib')).create();
      expect(FileUtils.isFlutterProject(tempDir.path), isFalse);
    });

    test('hasAndroidFolder returns true when android exists', () async {
      await Directory(p.join(tempDir.path, 'android')).create();
      expect(FileUtils.hasAndroidFolder(tempDir.path), isTrue);
    });

    test('hasIosFolder returns true when ios exists', () async {
      await Directory(p.join(tempDir.path, 'ios')).create();
      expect(FileUtils.hasIosFolder(tempDir.path), isTrue);
    });
  });
}
