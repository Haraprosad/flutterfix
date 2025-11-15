import 'package:mason_logger/mason_logger.dart';
import '../utils/file_utils.dart';

/// Rollback Command - Restore files from backups
///
/// This command allows users to undo changes made by FlutterFix
/// by restoring files from automatic backups.
class RollbackCommand {
  final Logger logger;
  final String projectPath;
  final bool listOnly;
  final String? backupId;
  final bool latest;
  final bool clearAll;

  RollbackCommand(
    this.logger,
    this.projectPath, {
    this.listOnly = false,
    this.backupId,
    this.latest = false,
    this.clearAll = false,
  });

  Future<void> execute() async {
    _printHeader();

    // Clear all backups
    if (clearAll) {
      await _clearAllBackups();
      return;
    }

    // List backups
    if (listOnly) {
      await _listBackups();
      return;
    }

    // Restore latest backup
    if (latest) {
      await _restoreLatestBackup();
      return;
    }

    // Restore specific backup
    if (backupId != null) {
      await _restoreSpecificBackup(backupId!);
      return;
    }

    // Interactive restore
    await _interactiveRestore();
  }

  Future<void> _listBackups() async {
    logger.info('📋 Listing all backups...\n');

    final backups = await FileUtils.listBackups(projectPath);

    if (backups.isEmpty) {
      logger.warn('⚠️  No backups found for this project');
      logger.info('');
      logger.info('💡 Backups are created automatically when you run:');
      logger.info('   • flutterfix sync');
      return;
    }

    logger.info('Found ${backups.length} backup(s):\n');

    for (int i = 0; i < backups.length; i++) {
      final backup = backups[i];
      final number = i + 1;
      final date = _formatDate(backup.timestamp);

      logger.info('[$number] ${backup.originalPath}');
      logger.info('    ID: ${backup.id}');
      logger.info('    Date: $date');
      logger.info('    Description: ${backup.description}');
      logger.info('');
    }

    logger.info('💡 To restore a backup:');
    logger.info('   flutterfix rollback --id <backup-id>');
    logger.info('   flutterfix rollback --latest');
  }

  Future<void> _restoreLatestBackup() async {
    logger.info('🔄 Restoring latest backup...\n');

    final backup = await FileUtils.getLatestBackup(projectPath);

    if (backup == null) {
      logger.err('❌ No backups found');
      return;
    }

    logger.info('Latest backup:');
    logger.info('  File: ${backup.originalPath}');
    logger.info('  Date: ${_formatDate(backup.timestamp)}');
    logger.info('  Description: ${backup.description}');
    logger.info('');

    final confirmed = logger.confirm(
      '? Restore this backup?',
      defaultValue: true,
    );

    if (!confirmed) {
      logger.info('❌ Rollback cancelled');
      return;
    }

    await _performRestore(backup);
  }

  Future<void> _restoreSpecificBackup(String id) async {
    logger.info('🔄 Restoring backup $id...\n');

    final backups = await FileUtils.listBackups(projectPath);
    final backup = backups.where((b) => b.id == id).firstOrNull;

    if (backup == null) {
      logger.err('❌ Backup not found: $id');
      logger.info('');
      logger.info('💡 List available backups:');
      logger.info('   flutterfix rollback --list');
      return;
    }

    await _performRestore(backup);
  }

  Future<void> _interactiveRestore() async {
    logger.info('🔄 Interactive Rollback\n');

    final backups = await FileUtils.listBackups(projectPath);

    if (backups.isEmpty) {
      logger.warn('⚠️  No backups found for this project');
      logger.info('');
      logger.info('💡 Backups are created automatically when you run:');
      logger.info('   • flutterfix sync');
      return;
    }

    logger.info('Available backups:\n');

    for (int i = 0; i < backups.length; i++) {
      final backup = backups[i];
      final number = i + 1;
      final date = _formatDate(backup.timestamp);

      logger.info('[$number] ${backup.originalPath}');
      logger.info('    Date: $date');
      logger.info('    ${backup.description}');
      logger.info('');
    }

    // Prompt for selection
    final selection = logger.prompt(
      '? Select backup to restore (1-${backups.length}, or 0 to cancel):',
    );

    final index = int.tryParse(selection);

    if (index == null || index < 0 || index > backups.length) {
      logger.err('❌ Invalid selection');
      return;
    }

    if (index == 0) {
      logger.info('❌ Rollback cancelled');
      return;
    }

    final selectedBackup = backups[index - 1];
    await _performRestore(selectedBackup);
  }

  Future<void> _performRestore(BackupInfo backup) async {
    try {
      logger.info('');
      final progress = logger.progress('Restoring ${backup.originalPath}');

      await FileUtils.restoreBackup(backup);

      progress.complete('Restored');

      logger.success('');
      logger.success('✅ Backup restored successfully!');
      logger.info('');
      logger.info('📁 Restored file: ${backup.originalPath}');

      // Ask if user wants to delete the backup
      logger.info('');
      final deleteBackup = logger.confirm(
        '? Delete this backup?',
        defaultValue: false,
      );

      if (deleteBackup) {
        await FileUtils.deleteBackup(projectPath, backup);
        logger.success('✅ Backup deleted');
      }
    } catch (e) {
      logger.err('');
      logger.err('❌ Failed to restore backup: $e');
      logger.info('');
      logger.info('💡 The backup file may have been moved or deleted');
    }
  }

  Future<void> _clearAllBackups() async {
    logger.warn('⚠️  Clear all backups?\n');

    final backups = await FileUtils.listBackups(projectPath);

    if (backups.isEmpty) {
      logger.info('No backups to clear');
      return;
    }

    logger.info('This will delete ${backups.length} backup(s)');
    logger.info('');

    final confirmed = logger.confirm(
      '? Are you sure?',
      defaultValue: false,
    );

    if (!confirmed) {
      logger.info('❌ Cancelled');
      return;
    }

    await FileUtils.clearAllBackups(projectPath);
    logger.success('✅ All backups cleared');
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  void _printHeader() {
    logger.info('╔═══════════════════════════════════════════╗');
    logger.info('║      ⏮️  FlutterFix Rollback ⏮️           ║');
    logger.info('║   Restore Files from Backups              ║');
    logger.info('╚═══════════════════════════════════════════╝');
    logger.info('');
  }
}
