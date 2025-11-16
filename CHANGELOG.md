## 1.2.3

### 🐛 Critical Bug Fix

* **Fixed version_map.yaml loading for globally installed package**
  - Added `Isolate.resolvePackageUri()` for proper package resource resolution
  - Works correctly when installed via `dart pub global activate flutterfix`
  - Supports multiple installation scenarios:
    - Published packages from pub.dev
    - Path-activated local packages
    - Development mode
  - Fixed FVM Flutter version detection from `.fvm/fvm_config.json`
  - Updated `sync_command.dart` to use FlutterInstaller's loadVersionMap method

### ✅ Tested Scenarios

* ✓ Global installation from pub.dev
* ✓ Path-activated local development
* ✓ Running with `--original --install-flutter` flags
* ✓ FVM integration with auto-detection

## 1.2.2

### 📈 Pub Points Improvement (130 → 160 points)

* **Added example/** - Created comprehensive example demonstrating all FlutterFix commands (+10 points)
* **Fixed regex syntax** - Corrected invalid regular expression patterns in gradle_detector.dart (+10 points)
  - Fixed AGP version detection regex
  - Fixed Kotlin version detection regex
* **Updated dependencies** - Upgraded to latest stable versions (+10 points)
  - `mason_logger`: ^0.2.0 → ^0.3.0
  - `process_run`: ^0.14.0 → ^1.0.0

### ✅ Quality Improvements

* Zero analyzer errors, warnings, or lints
* All 64 tests passing
* Example demonstrates real-world usage patterns
* Full compatibility with latest dependencies

## 1.2.1

### 🐛 Bug Fixes

* **Fixed version_map.yaml loading** - Improved path resolution for globally installed package
  - Now correctly finds version_map.yaml when installed via `dart pub global activate flutterfix`
  - Prioritizes local development version over published versions
  - Sorts published versions to use the latest available
  - Fixes "FileSystemException: File not found" error when running globally installed FlutterFix

## 1.2.0

### 🎯 Major Features

* **NEW: `--original` flag** - Automatically detects and uses the project's original Flutter version from `.metadata`
* **NEW: `--install-flutter` flag** - Auto-installs detected Flutter version using FVM
* **Complete version map** - Added all 176 stable Flutter versions from v1.0.0 to 3.38.1
* **Smart version detection** - Reads `.metadata` file to determine original Flutter version used during project creation

### 🔧 Improvements

* Updated compatibility matrix with corrected AGP, Gradle, and Kotlin versions:
  - Flutter 3.24.x: Kotlin 2.0.0 → 2.0.10 for better stability
  - Flutter 3.22.x: AGP 8.1.0 → 8.3.0, Gradle 8.3 → 8.5, Kotlin 1.9.0 → 1.9.24
  - Flutter 3.19.x: AGP 8.0.0 → 8.1.4 (deprecated version removed), compile_sdk 33 → 34
  - Flutter 3.16.x: AGP 7.4.0 → 8.1.4, Gradle 7.6 → 8.3, Kotlin 1.8.0 → 1.9.0, compile_sdk 33 → 34
  - Flutter 3.13.x: AGP 7.3.0 → 7.4.2, Gradle 7.5 → 7.6, Kotlin 1.7.10 → 1.8.22
* Fixed type casting issues when reading version map (int vs string handling)
* Improved version comparison logic to handle semantic versions with "v" prefix and hotfix suffixes
* Enhanced FVM integration with automatic project configuration via `.fvm/fvm_config.json`

### 📚 Documentation

* Completely redesigned README with practical workflow examples
* Added "Most Common Use Cases" section with 3 clear scenarios
* Detailed command reference with all available flags
* Real-world examples for cloning and running projects
* Clear explanation of `--original` flag benefits
* Pro tips for version management and troubleshooting

### 🐛 Bug Fixes

* Fixed version map type handling for SDK values (min_sdk, compile_sdk, target_sdk)
* Fixed version string parsing for versions with "+" or "v" characters
* Improved error handling when Flutter is not installed

### 💡 Usage Examples

One-command solution for cloned projects:
```bash
flutterfix sync --original --install-flutter
```

This automatically:
- Detects original Flutter version from `.metadata`
- Installs that version using FVM
- Applies version-compatible Gradle, AGP, Kotlin configs
- Configures `.fvm/fvm_config.json`
- Cleans caches and updates dependencies

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
