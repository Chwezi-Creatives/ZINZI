import 'dart:io';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:path/path.dart' as path;

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  if (dryRun) {
    print('🔄 Running in dry-run mode - no files will be modified');
  }
  try {
    // Get the project root directory (one level up from scripts/)
    final scriptDir = File(Platform.script.toFilePath()).parent.path;
    final projectRoot = Directory(path.dirname(scriptDir));
    final changeLogPath = path.join(projectRoot.path, 'debugprint_change_log.json');
    final changeLogFile = File(changeLogPath);

    // Check if change log exists
    if (!changeLogFile.existsSync()) {
      stderr.writeln(
          'Error: No change log found at $changeLogPath. Nothing to undo.');
      exit(1);
    }

    print('Reading change log from ${changeLogFile.path}...');
    final changeLog =
        jsonDecode(changeLogFile.readAsStringSync()) as Map<String, dynamic>;

    if (changeLog.isEmpty) {
      print('No changes to undo. Change log is empty.');
      changeLogFile.deleteSync();
      exit(0);
    }

    print('Found ${changeLog.length} files to restore...');
    int successCount = 0;
    int failedCount = 0;

    // Process each file in the change log
    for (final entry in changeLog.entries) {
      // Convert relative paths in the log to absolute paths
      final filePath = path.isAbsolute(entry.key) 
          ? entry.key 
          : path.normalize(path.join(projectRoot.path, entry.key));
      final file = File(filePath);
      final relativePath = path.relative(filePath);

      if (!file.existsSync()) {
        print('⚠️  Warning: File not found: $relativePath');
        failedCount++;
        continue;
      }

      try {
        final data = entry.value as Map<String, dynamic>;
        if (!data.containsKey('original_content')) {
          print(
              '❌ Error: Invalid change log entry for $relativePath - missing original content');
          failedCount++;
          continue;
        }

        final originalContent = data['original_content'] as String;
        final addedImport = data['added_import'] ?? false;

        if (!dryRun) {
          // Create backup before making changes
          final backupPath = '$filePath.bak';
          File(backupPath).writeAsStringSync(file.readAsStringSync());

          // Restore original content
          file.writeAsStringSync(originalContent);

          // Remove backup if successful
          File(backupPath).deleteSync();
        }

        print('✅ Restored: $relativePath');
        successCount++;
      } catch (e, stackTrace) {
        print('❌ Error restoring $relativePath: $e');
        print('Stack trace: $stackTrace');
        failedCount++;
      }
    }

    // Delete change log if all operations were successful and not in dry-run mode
    if (failedCount == 0) {
      if (!dryRun) {
        changeLogFile.deleteSync();
        print('\n✅ Successfully restored $successCount files.');
        print('Change log removed.');
      } else {
        print('\n📋 Dry run complete! Would restore $successCount files.');
        print(
            'To apply these changes, run the script without the --dry-run flag.');
      }
    } else {
      print(
          '\n⚠️  Warning: Failed to restore $failedCount out of ${changeLog.length} files.');
      if (!dryRun) {
        print(
            'Change log preserved at ${changeLogFile.path} for another attempt.');
      }
      exit(1);
    }
  } catch (e, stackTrace) {
    stderr.writeln('\n❌ Fatal error during undo operation:');
    stderr.writeln(e);
    stderr.writeln('Stack trace: $stackTrace');
    exit(1);
  }
}
