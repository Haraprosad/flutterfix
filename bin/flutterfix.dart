import 'dart:io';
import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:flutterfix/flutterfix.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addCommand('doctor')
    ..addCommand(
        'sync',
        ArgParser()
          ..addFlag(
            'original',
            negatable: false,
            help:
                'Use original Flutter version from .metadata and apply compatible configs',
          )
          ..addFlag(
            'install-flutter',
            negatable: false,
            help: 'Auto-install detected Flutter version if not present',
          )
          ..addFlag(
            'fix-dependencies',
            negatable: false,
            help: 'Automatically fix Dart package dependency conflicts',
          ))
    ..addCommand('upgrade')
    ..addCommand(
        'install',
        ArgParser()
          ..addOption(
            'version',
            help: 'Specific Flutter version to install (e.g., 3.24)',
          )
          ..addFlag(
            'list',
            abbr: 'l',
            negatable: false,
            help: 'List available Flutter versions',
          )
          ..addFlag(
            'info',
            abbr: 'i',
            negatable: false,
            help: 'Show version compatibility info',
          )
          ..addFlag(
            'no-fvm',
            negatable: false,
            help: 'Install without using FVM (standalone)',
          ))
    ..addCommand(
        'rollback',
        ArgParser()
          ..addFlag(
            'list',
            abbr: 'l',
            negatable: false,
            help: 'List all available backups',
          )
          ..addOption(
            'id',
            help: 'Restore specific backup by ID',
          )
          ..addFlag(
            'latest',
            negatable: false,
            help: 'Restore the most recent backup',
          )
          ..addFlag(
            'clear',
            negatable: false,
            help: 'Clear all backups',
          ))
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message',
    )
    ..addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Show version information',
    )
    ..addOption(
      'path',
      abbr: 'p',
      help: 'Path to Flutter project',
      defaultsTo: '.',
    );

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      _printHelp(parser);
      exit(0);
    }

    if (results['version'] as bool) {
      _printVersion();
      exit(0);
    }

    final projectPath = results['path'] as String;
    final logger = Logger();

    // Validate project path
    if (!Directory(projectPath).existsSync()) {
      logger.err('❌ Error: Directory not found: $projectPath');
      exit(1);
    }

    final command = results.command;

    if (command != null) {
      await _executeCommand(command, projectPath, logger);
    } else {
      // Default to sync
      final syncCmd = SyncCommand(logger, projectPath);
      await syncCmd.execute();
    }
  } catch (e) {
    print('❌ Error: $e');
    exit(1);
  }
}

Future<void> _executeCommand(
  ArgResults command,
  String projectPath,
  Logger logger,
) async {
  switch (command.name) {
    case 'doctor':
      final doctorCmd = DoctorCommand(logger, projectPath);
      await doctorCmd.execute();
      break;

    case 'sync':
      final syncCmd = SyncCommand(
        logger,
        projectPath,
        useOriginal: command['original'] as bool,
        autoInstallFlutter: command['install-flutter'] as bool,
        fixDependencies: command['fix-dependencies'] as bool,
      );
      await syncCmd.execute();
      break;

    case 'upgrade':
      final upgradeCmd = UpgradeCommand(logger);
      await upgradeCmd.execute();
      break;

    case 'install':
      final installCmd = InstallCommand(
        logger,
        projectPath,
        specificVersion: command['version'] as String?,
        listVersions: command['list'] as bool,
        showInfo: command['info'] as bool,
        useFvm: !(command['no-fvm'] as bool),
      );
      await installCmd.execute();
      break;

    case 'rollback':
      final rollbackCmd = RollbackCommand(
        logger,
        projectPath,
        listOnly: command['list'] as bool,
        backupId: command['id'] as String?,
        latest: command['latest'] as bool,
        clearAll: command['clear'] as bool,
      );
      await rollbackCmd.execute();
      break;

    default:
      print('Unknown command: ${command.name}');
      exit(1);
  }
}

void _printHelp(ArgParser parser) {
  print('''
╔═══════════════════════════════════════════╗
║       🔧 FlutterFix v1.0.0 🔧             ║
║   Auto-fix Flutter Build Errors           ║
╚═══════════════════════════════════════════╝

A zero-config CLI tool that automatically fixes Flutter & Android 
build errors — resolving Gradle, Kotlin, Java, and Flutter version 
mismatches with one command.

USAGE:
  flutterfix [command] [options]

COMMANDS:
  doctor      Diagnose project issues (non-destructive)
  sync        Fix all detected issues (default)
  install     Install compatible Flutter version
  rollback    Restore files from backups
  upgrade     Update FlutterFix to latest version

OPTIONS:
${parser.usage}

EXAMPLES:
  # Fix the current Flutter project
  flutterfix

  # or explicitly
  flutterfix sync

  # Diagnose without fixing
  flutterfix doctor

  # Install compatible Flutter version automatically
  flutterfix install

  # List available Flutter versions
  flutterfix install --list

  # Install specific Flutter version
  flutterfix install --version 3.24

  # Undo last changes (restore from backup)
  flutterfix rollback

  # List all backups
  flutterfix rollback --list

  # Restore latest backup
  flutterfix rollback --latest

  # Fix a specific project
  flutterfix --path /path/to/project

  # Upgrade FlutterFix
  flutterfix upgrade

WHAT IT FIXES:
  ✅ Gradle version compatibility
  ✅ Android Gradle Plugin (AGP) version
  ✅ Kotlin version compatibility
  ✅ Java compile options
  ✅ Android SDK versions (min, target, compile)
  ✅ Build cache issues
  ✅ Dependency resolution

For more information, visit:
https://github.com/haraprosad/flutterfix
''');
}

void _printVersion() {
  print('FlutterFix v1.0.0');
  print('A professional Flutter project repair tool');
  print('https://github.com/haraprosad/flutterfix');
}
