import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flutterfix/flutterfix.dart';

void main() {
  late Directory tempDir;
  late String testProjectPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flutterfix_test_');
    testProjectPath = tempDir.path;

    // Create a simple Flutter project structure
    await Directory(p.join(testProjectPath, 'android')).create(recursive: true);
    await File(p.join(testProjectPath, 'pubspec.yaml'))
        .writeAsString('name: test_project\n');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('BackupInfo', () {
    test('should serialize to JSON', () {
      final backup = BackupInfo(
        id: '123456',
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
        originalPath: p.join('android', 'build.gradle'),
        backupPath:
            p.join('.flutterfix', 'backups', 'build.gradle.backup.123456'),
        description: 'Test backup',
        projectPath: '/test/project',
      );

      final json = backup.toJson();

      expect(json['id'], equals('123456'));
      expect(json['originalPath'], equals(p.join('android', 'build.gradle')));
      expect(json['description'], equals('Test backup'));
    });

    test('should deserialize from JSON', () {
      final json = {
        'id': '123456',
        'timestamp': '2024-01-01T12:00:00.000',
        'originalPath': p.join('android', 'build.gradle'),
        'backupPath':
            p.join('.flutterfix', 'backups', 'build.gradle.backup.123456'),
        'description': 'Test backup',
        'projectPath': '/test/project',
      };

      final backup = BackupInfo.fromJson(json);

      expect(backup.id, equals('123456'));
      expect(backup.originalPath, equals(p.join('android', 'build.gradle')));
      expect(backup.description, equals('Test backup'));
      expect(backup.timestamp.year, equals(2024));
    });
  });

  group('FileUtils Backup', () {
    test('should create backup directory', () async {
      final backupDir = await FileUtils.getBackupDirectory(testProjectPath);
      await FileUtils.ensureDir(backupDir);

      expect(Directory(backupDir).existsSync(), isTrue);
      expect(backupDir, contains('.flutterfix'));
      expect(backupDir, contains('backups'));
    });

    test('should create backup of a file', () async {
      final testFile = p.join(testProjectPath, 'android', 'build.gradle');
      await File(testFile).writeAsString('test content');

      final backup = await FileUtils.createBackup(
        testProjectPath,
        testFile,
        'Test backup',
      );

      expect(backup.id, isNotEmpty);
      expect(backup.originalPath, equals(p.join('android', 'build.gradle')));
      expect(backup.description, equals('Test backup'));
      expect(File(backup.backupPath).existsSync(), isTrue);
    });

    test('should list backups', () async {
      final testFile = p.join(testProjectPath, 'android', 'build.gradle');
      await File(testFile).writeAsString('test content');

      await FileUtils.createBackup(testProjectPath, testFile, 'Backup 1');
      await Future.delayed(Duration(milliseconds: 10));
      await FileUtils.createBackup(testProjectPath, testFile, 'Backup 2');

      final backups = await FileUtils.listBackups(testProjectPath);

      expect(backups.length, equals(2));
      expect(backups[0].description, equals('Backup 2')); // Latest first
      expect(backups[1].description, equals('Backup 1'));
    });

    test('should get latest backup', () async {
      final testFile = p.join(testProjectPath, 'android', 'build.gradle');
      await File(testFile).writeAsString('test content');

      await FileUtils.createBackup(testProjectPath, testFile, 'Old backup');
      await Future.delayed(Duration(milliseconds: 10));
      await FileUtils.createBackup(testProjectPath, testFile, 'Latest backup');

      final latest = await FileUtils.getLatestBackup(testProjectPath);

      expect(latest, isNotNull);
      expect(latest!.description, equals('Latest backup'));
    });

    test('should restore backup', () async {
      final testFile = p.join(testProjectPath, 'android', 'build.gradle');
      await File(testFile).writeAsString('original content');

      final backup = await FileUtils.createBackup(
        testProjectPath,
        testFile,
        'Backup before change',
      );

      // Modify the file
      await File(testFile).writeAsString('modified content');
      expect(await File(testFile).readAsString(), equals('modified content'));

      // Restore backup
      await FileUtils.restoreBackup(backup);

      expect(await File(testFile).readAsString(), equals('original content'));
    });

    test('should delete backup', () async {
      final testFile = p.join(testProjectPath, 'android', 'build.gradle');
      await File(testFile).writeAsString('test content');

      final backup = await FileUtils.createBackup(
        testProjectPath,
        testFile,
        'Backup to delete',
      );

      expect(File(backup.backupPath).existsSync(), isTrue);

      await FileUtils.deleteBackup(testProjectPath, backup);

      expect(File(backup.backupPath).existsSync(), isFalse);

      final backups = await FileUtils.listBackups(testProjectPath);
      expect(backups, isEmpty);
    });

    test('should clear all backups', () async {
      final testFile = p.join(testProjectPath, 'android', 'build.gradle');
      await File(testFile).writeAsString('test content');

      await FileUtils.createBackup(testProjectPath, testFile, 'Backup 1');
      await FileUtils.createBackup(testProjectPath, testFile, 'Backup 2');
      await FileUtils.createBackup(testProjectPath, testFile, 'Backup 3');

      final backupsBefore = await FileUtils.listBackups(testProjectPath);
      expect(backupsBefore.length, equals(3));

      await FileUtils.clearAllBackups(testProjectPath);

      final backupsAfter = await FileUtils.listBackups(testProjectPath);
      expect(backupsAfter, isEmpty);
    });

    test('should return empty list when no backups exist', () async {
      final backups = await FileUtils.listBackups(testProjectPath);
      expect(backups, isEmpty);
    });

    test('should return null when no latest backup exists', () async {
      final latest = await FileUtils.getLatestBackup(testProjectPath);
      expect(latest, isNull);
    });
  });
}
