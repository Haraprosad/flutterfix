## 1.1.2

* Added automatic PATH configuration for standalone Flutter installations
* Auto-detects shell type (zsh, bash, fish) and updates appropriate config file
* Windows support: Automatically updates User PATH environment variable
* Smart Flutter version detection based on Dart SDK constraints
* Improved version matching algorithm for better compatibility
* Enhanced error messages with helpful suggestions

## 1.1.1

* Fixed critical bug: version_map.yaml now loads from FlutterFix package instead of user's project
* Improved path resolution for global installations
* Better error messages when version_map.yaml is not found

## 1.1.0

* Updated version compatibility map with all stable Flutter versions from 2.0 to 3.38
* Added support for Flutter 3.38, 3.35, 3.32, 3.29 with latest Gradle and Kotlin versions
* Improved compatibility with Dart SDK 3.5.3+
* Updated default versions to Gradle 8.11, AGP 8.7.3, Kotlin 2.1.0

## 1.0.0

* Initial release
* Smart analysis to detect common Flutter issues and anti-patterns
* Auto-fix for deprecated code and common problems
* Detailed analysis reports with actionable insights
* Cross-platform support (Windows, macOS, Linux)
* Simple CLI commands for easy project management
* Flutter version detection and compatibility checking
* Automatic backup creation before applying fixes
* Comprehensive test coverage across platforms
