import 'package:mason_logger/mason_logger.dart';
import '../installer/flutter_installer.dart';

/// Install Command - Install compatible Flutter version
///
/// This command helps users install the correct Flutter version
/// for their project automatically or manually specify a version.
class InstallCommand {
  final Logger logger;
  final String projectPath;
  final String? specificVersion;
  final bool listVersions;
  final bool showInfo;
  final bool useFvm;

  InstallCommand(
    this.logger,
    this.projectPath, {
    this.specificVersion,
    this.listVersions = false,
    this.showInfo = false,
    this.useFvm = true,
  });

  Future<void> execute() async {
    _printHeader();

    final installer = FlutterInstaller(logger);
    await installer.loadVersionMap();

    // List available versions
    if (listVersions) {
      await _listVersions(installer);
      return;
    }

    // Show version info
    if (showInfo && specificVersion != null) {
      installer.printVersionInfo(specificVersion!);
      return;
    }

    // Install specific version
    if (specificVersion != null) {
      await _installSpecificVersion(installer, specificVersion!);
      return;
    }

    // Auto-install based on project requirements
    await _autoInstall(installer);
  }

  Future<void> _listVersions(FlutterInstaller installer) async {
    logger.info('📋 Available Flutter Versions:\n');

    final versions = installer.getAvailableVersions();

    if (versions.isEmpty) {
      logger.warn('⚠️  No versions found in compatibility matrix');
      return;
    }

    // Check installed versions
    final installed = await installer.listInstalledVersions();

    for (final version in versions) {
      final isInstalled = installed.contains(version);
      final marker = isInstalled ? '✅' : '  ';
      final details = installer.getVersionDetails(version);

      logger.info('$marker Flutter $version');
      if (details != null) {
        logger.info('   └─ Gradle ${details['gradle']}, '
            'AGP ${details['agp']}, '
            'Kotlin ${details['kotlin']}, '
            'Java ${details['java']}+');
      }
    }

    if (installed.isNotEmpty) {
      logger.info('\n✅ = Already installed');
    }
  }

  Future<void> _installSpecificVersion(
    FlutterInstaller installer,
    String version,
  ) async {
    logger.info('🎯 Installing Flutter $version...\n');

    // Show version details
    installer.printVersionInfo(version);
    logger.info('');

    // Check if FVM should be used
    if (useFvm) {
      final hasFvm = await installer.isFvmInstalled();

      if (!hasFvm) {
        logger.info('📦 FVM not found. Installing FVM first...\n');
        final installed = await installer.installFvm();

        if (!installed) {
          logger.warn('⚠️  FVM installation failed.');
          logger.info('💡 Falling back to standalone installation...\n');
          await installer.installStandalone(version);
          return;
        }
      }

      // Install with FVM
      final success = await installer.installWithFvm(version);

      if (success) {
        // Ask if user wants to use this version in current project
        logger.info('');
        final useInProject = logger.confirm(
          '? Set Flutter $version for this project?',
          defaultValue: true,
        );

        if (useInProject) {
          await installer.useVersionInProject(projectPath, version);
        }
      }
    } else {
      // Standalone installation
      await installer.installStandalone(version);
    }
  }

  Future<void> _autoInstall(FlutterInstaller installer) async {
    logger.info('🤖 Auto-detecting required Flutter version...\n');

    final success = await installer.autoInstall(projectPath);

    if (success) {
      logger.info('');
      logger.success('╔═══════════════════════════════════════════╗');
      logger.success('║   ✅ Flutter installation complete!       ║');
      logger.success('╚═══════════════════════════════════════════╝');
      logger.info('');
      logger.info('💡 Next steps:');
      logger.info('   1. Run: fvm flutter pub get');
      logger.info('   2. Run: fvm flutter run');
      logger.info('');
      logger.info('💡 Or run flutterfix sync to configure the project');
    } else {
      logger.err('');
      logger.err('❌ Installation failed or version could not be determined');
      logger.info('');
      logger.info('💡 Try:');
      logger.info(
          '   • flutterfix install --list        (see available versions)');
      logger.info(
          '   • flutterfix install --version 3.24 (install specific version)');
    }
  }

  void _printHeader() {
    logger.info('╔═══════════════════════════════════════════╗');
    logger.info('║     📦 Flutter Installer v1.0.0 📦        ║');
    logger.info('║   Auto-install Compatible Flutter         ║');
    logger.info('╚═══════════════════════════════════════════╝');
    logger.info('');
  }
}
