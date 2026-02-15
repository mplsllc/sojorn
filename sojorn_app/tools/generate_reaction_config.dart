#!/usr/bin/env dart

import 'dart:io';
import 'dart:convert';

/// Script to generate reaction_config.json by scanning reaction folders
/// Run this script whenever you add new reaction files or folders

void main() async {
  final reactionsDir = Directory('assets/reactions');
  if (!await reactionsDir.exists()) {
    print('Error: assets/reactions directory not found');
    return;
  }

  final reactionSets = <String, Map<String, dynamic>>{};
  
  // Add default emoji set
  reactionSets['emoji'] = {
    'type': 'emoji',
    'reactions': [
      '❤️', '👍', '😂', '😮', '😢', '😡',
      '🎉', '🔥', '👏', '🙏', '💯', '🤔',
      '😍', '🤣', '😊', '👌', '🙌', '💪',
      '🎯', '⭐', '✨', '🌟', '💫', '☀️',
    ],
  };

  // Scan each folder in reactions directory
  await for (final entity in reactionsDir.list()) {
    if (entity is Directory && entity.path.contains('reactions\\') || entity.path.contains('reactions/')) {
      final folderName = entity.path.split(Platform.pathSeparator).last;
      
      // Skip emoji folder (handled above)
      if (folderName == 'emoji') continue;
      
      print('Scanning folder: $folderName');
      
      final files = <String>[];
      final fileTypes = <String>{};
      
      // Scan all files in the folder
      await for (final file in (entity as Directory).list()) {
        if (file is File) {
          final fileName = file.path.split(Platform.pathSeparator).last;
          
          // Only include image files
          if (fileName.endsWith('.png') || fileName.endsWith('.svg')) {
            files.add(fileName);
            fileTypes.add(fileName.split('.').last);
          }
        }
      }
      
      if (files.isNotEmpty) {
        reactionSets[folderName] = {
          'type': 'folder',
          'folder': folderName,
          'file_types': fileTypes.toList(),
          'files': files, // Explicit file list since we can't discover at runtime
        };
        
        print('  Found ${files.length} files: ${files.take(5).join(', ')}${files.length > 5 ? '...' : ''}');
      } else {
        print('  ⚠️  No reaction files found, skipping folder');
      }
    }
  }

  // Generate configuration
  final config = {
    'reaction_sets': reactionSets,
    'generated_at': DateTime.now().toIso8601String(),
    'total_sets': reactionSets.length,
  };

  // Write configuration file
  final configFile = File('assets/reactions/reaction_config.json');
  await configFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(config)
  );

  print('\n✅ Generated reaction_config.json with ${reactionSets.length} reaction sets');
  final activeFolders = reactionSets.keys.where((k) => k != 'emoji').toList();
  if (activeFolders.isNotEmpty) {
    print('📁 Active folders: ${activeFolders.join(', ')}');
  } else {
    print('📁 No active folders found (only emoji set)');
  }
  
  // Check for empty folders
  final allFolders = <String>[];
  await for (final entity in reactionsDir.list()) {
    if (entity is Directory) {
      final folderName = entity.path.split(Platform.pathSeparator).last;
      if (folderName != 'emoji') allFolders.add(folderName);
    }
  }
  
  final emptyFolders = allFolders.where((folder) => !activeFolders.contains(folder)).toList();
  if (emptyFolders.isNotEmpty) {
    print('🗂️  Empty folders (ignored): ${emptyFolders.join(', ')}');
  }
  
  print('⚠️  Remember to run "flutter pub get" and restart your app');
}
