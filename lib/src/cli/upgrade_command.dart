import 'package:mason_logger/mason_logger.dart';
import '../runner/process_runner.dart';

class UpgradeCommand {
  final Logger logger;

  UpgradeCommand(this.logger);

  Future<void> execute() async {
    logger.info('🔄 Checking for FlutterFix updates...\n');

    // Check current version
    final result = await ProcessRunner.dart([
      'pub',
      'global',
      'list',
    ]);

    if (result.success && result.stdout.contains('flutterfix')) {
      logger.info('Current installation found');
    }

    // Upgrade
    final progress = logger.progress('Upgrading FlutterFix');

    final upgradeResult = await ProcessRunner.dart([
      'pub',
      'global',
      'activate',
      'flutterfix',
    ]);

    if (upgradeResult.success) {
      progress.complete('FlutterFix upgraded successfully');
      logger.success('✅ You\'re using the latest version!');
    } else {
      progress.fail('Upgrade failed');
      logger.err(upgradeResult.stderr);
    }
  }
}
