import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

final changeLog = <String, Map<String, dynamic>>{};

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  if (dryRun) {
    print('🚀 Running in dry-run mode - no files will be modified');
  }

  // Find the project root directory (one level up from scripts directory)
  final scriptDir = File(Platform.script.toFilePath()).parent.path;
  final projectRoot = Directory(path.dirname(scriptDir));
  final libDir = Directory(path.join(projectRoot.path, 'lib'));
  
  if (!libDir.existsSync()) {
    print('Error: lib directory not found at ${libDir.path}');
    exit(1);
  }

  // Create change log file in the project root
  final changeLogFile = File(path.join(projectRoot.path, 'debugprint_change_log.json'));
  if (changeLogFile.existsSync()) {
    print('Error: Change log already exists. Run undo script first.');
    exit(1);
  }

  processDirectory(libDir, dryRun: dryRun);

  // Write change log if not in dry-run mode
  if (!dryRun) {
    changeLogFile.writeAsStringSync(jsonEncode(changeLog));
    print('✅ Conversion complete! Change log created at ${changeLogFile.path}');
  } else {
    print(
        '\n📋 Dry run complete! Found ${changeLog.length} files that would be modified.');
    print('To apply these changes, run the script without the --dry-run flag.');
  }
}

void processDirectory(Directory directory, {bool dryRun = false}) {
  directory.listSync(recursive: true).where((entity) {
    return entity is File &&
        (entity.path.endsWith('.dart') || entity.path.endsWith('.dartp'));
  }).forEach((entity) {
    processFile(entity as File, dryRun: dryRun);
  });
}

void processFile(File file, {bool dryRun = false}) {
  try {
    final relativePath = path.relative(file.path);
    String content = file.readAsStringSync();
    final originalContent = content;
    final changes = <String, String>{};

    // Find all print statements that aren't already debugPrint
    final printRegex = RegExp(r'(?<![._a-zA-Z0-9])(print)(\s*)\(');
    final matches = printRegex.allMatches(content).toList();

    // Process matches in reverse order to preserve positions
    for (final match in matches.reversed) {
      final fullMatch = match.group(0)!;
      final whitespace = match.group(2)!;
      final position = match.start;

      // Store original
      changes[position.toString()] = fullMatch;

      // Replace in content
      content = content.replaceRange(
          position, position + fullMatch.length, 'debugPrint$whitespace(');
    }

    // Check for foundation import using a simpler pattern
    bool hasFoundationImport =
        content.contains("import 'package:flutter/foundation.dart'") ||
            content.contains('import "package:flutter/foundation.dart"');
    bool addedImport = false;

    if (!hasFoundationImport && matches.isNotEmpty) {
      content = addFoundationImport(content);
      addedImport = true;
    }

    if (content != originalContent) {
      if (!dryRun) {
        file.writeAsStringSync(content);
      }
      changeLog[relativePath] = {
        'original_content': originalContent,
        'changes': changes,
        'added_import': addedImport
      };
      final changesSummary = [
        if (changes.isNotEmpty) '${changes.length} print statements replaced',
        if (addedImport) 'foundation import added',
      ].whereType<String>().join(', ');

      print(
          '${dryRun ? '[DRY RUN] ' : ''}Would process: $relativePath ($changesSummary)');
    }
  } catch (e) {
    print('Error processing ${file.path}: $e');
  }
}

String addFoundationImport(String content) {
  final lines = LineSplitter.split(content).toList();
  int lastImportIndex = -1;

  // Find the last import statement
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].trim().startsWith('import ')) {
      lastImportIndex = i;
    }
  }

  final importLine = "import 'package:flutter/foundation.dart';";
  if (lastImportIndex != -1) {
    // Insert after the last import
    lines.insert(lastImportIndex + 1, importLine);
  } else {
    // No imports found, add at the top
    lines.insert(0, importLine);
  }

  return lines.join('\n');
}
