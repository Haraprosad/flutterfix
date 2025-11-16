# FlutterFix Examples

This guide provides step-by-step examples for common FlutterFix usage scenarios.

---

## Example 1: Fix a Cloned Flutter Project with Original Version

When you clone a Flutter project and want to run it with the exact Flutter version it was built with:

### Step 1: Navigate to the project directory

```bash
cd path/to/cloned-project
```

### Step 2: Run FlutterFix with original version detection

```bash
flutterfix sync --original --install-flutter
```

This command will:
- Detect the original Flutter version from `.flutter-plugins-dependencies` or `.metadata`
- Install that specific Flutter version using FVM
- Apply compatible Gradle, AGP, and Kotlin versions
- Update all build configuration files
- Clean caches and update dependencies

### Step 3: Run the project

```bash
flutter run
```

---

## Example 2: Install a Specific Flutter Version

If you want to use a specific version of Flutter for your project:

### Step 1: Choose and install the version

Install version 3.24.5 and cache it locally:

```bash
flutterfix install 3.24.5 --use-fvm
```

### Step 2: Navigate to your project

```bash
cd path/to/project
```

### Step 3: The installation automatically:
- Installs Flutter 3.24.5 via FVM
- Configures `.fvm/fvm_config.json`
- Applies compatible build tool versions:
  - Gradle: 8.7
  - AGP: 8.5.0
  - Kotlin: 2.0.10
  - Java: 17

---

## Example 3: Upgrade to Latest Flutter Version

Upgrade your project to the latest stable Flutter version:

### Step 1: Navigate to your project

```bash
cd path/to/project
```

### Step 2: Run the upgrade command

```bash
flutterfix upgrade --use-fvm
```

This will:
- Install the latest Flutter stable version
- Update all build tools to compatible versions
- Clean and rebuild dependencies

---

## Example 4: Quick Fix for Build Errors

If you have build errors due to version mismatches:

### Step 1: Navigate to your project

```bash
cd path/to/project
```

### Step 2: Run sync command

```bash
flutterfix sync
```

This will:
- Detect your current Flutter version
- Fix Gradle, AGP, and Kotlin version conflicts
- Update build configuration files
- Clean caches

---

## Example 5: Diagnose Project Issues

Check your project for compatibility issues:

```bash
cd path/to/project
flutterfix doctor
```

Output example:
```
╔═══════════════════════════════════════════╗
║       🏥 FlutterFix Doctor 🏥             ║
║   Diagnose Flutter Project Issues         ║
╚═══════════════════════════════════════════╝

✓ Flutter SDK: 3.24.5
✓ Gradle: 8.7
✓ AGP: 8.5.0
✓ Kotlin: 2.0.10
✓ Java: 17

✅ All versions are compatible!
```

---

## Example 6: Rollback Changes

If something goes wrong, revert to the previous configuration:

```bash
flutterfix rollback
```

This restores backed-up files from `.flutterfix_backup/`.

---

## Common Workflows

### Workflow A: Clone and Run a Project
```bash
git clone https://github.com/username/flutter-project.git
cd flutter-project
flutterfix sync --original --install-flutter
flutter pub get
flutter run
```

### Workflow B: Start Fresh with Latest Flutter
```bash
cd existing-project
flutterfix upgrade --use-fvm
flutter clean
flutter pub get
flutter run
```

### Workflow C: Fix Build Errors
```bash
cd problematic-project
flutterfix doctor          # Diagnose issues
flutterfix sync            # Fix version conflicts
flutter clean
flutter pub get
flutter run
```

---

## Installation Modes

### FVM Mode (Recommended)
```bash
flutterfix install 3.24.5 --use-fvm
```
- Uses FVM for version management
- Creates `.fvm/fvm_config.json`
- Easy to switch between versions
- Recommended for multi-project development

### Standalone Mode
```bash
flutterfix install 3.24.5 --standalone
```
- Direct git clone from Flutter repository
- Sets up PATH configuration
- Good for single-version environments

---

## Tips

1. **Always use `--original` flag when cloning projects** to preserve the development environment
2. **Use `--install-flutter` to automate Flutter installation** instead of manual FVM commands
3. **Run `flutterfix doctor` first** to understand current state before making changes
4. **Keep backups** - FlutterFix automatically creates `.flutterfix_backup/` before changes

---

For more information, visit the [FlutterFix GitHub repository](https://github.com/haraprosad/flutterfix).
