import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Service for cleaning up stale recording files on app startup.
class CleanupService {
  const CleanupService();

  /// Deletes leftover `report_*.m4a` files in the temp directory older than [maxAge].
  /// Never deletes [activeFilePath] (a file that the current session is actively using).
  Future<int> cleanupStaleAudioFiles({
    Duration maxAge = const Duration(hours: 24),
    String? activeFilePath,
    Future<Directory> Function()? getTempDir,
  }) async {
    int deletedCount = 0;
    try {
      final tempDir = await (getTempDir ?? getTemporaryDirectory)();
      if (!await tempDir.exists()) return 0;

      final now = DateTime.now();
      final entities = tempDir.listSync(followLinks: false);

      for (final entity in entities) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : '';
          if (fileName.startsWith('report_') && fileName.endsWith('.m4a')) {
            // Never delete the active file
            if (activeFilePath != null &&
                entity.path.replaceAll('\\', '/') ==
                    activeFilePath.replaceAll('\\', '/')) {
              continue;
            }

            try {
              final lastModified = await entity.lastModified();
              if (now.difference(lastModified) >= maxAge) {
                await entity.delete();
                deletedCount++;
                debugPrint('>>> [CleanupService] Deleted stale audio file: ${entity.path}');
              }
            } catch (e) {
              debugPrint('>>> [CleanupService] Could not delete ${entity.path}: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('>>> [CleanupService] Error during cleanup: $e');
    }
    return deletedCount;
  }
}
