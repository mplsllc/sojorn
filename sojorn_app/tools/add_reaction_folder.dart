#!/usr/bin/env dart

import 'dart:io';
import 'dart:convert';

/// Script to add new reaction folders to the reaction picker
/// Run this after creating a new folder with images and credit.md

void main() async {
  print('🔍 Scanning for new reaction folders...\n');
  
  final reactionsDir = Directory('assets/reactions');
  if (!await reactionsDir.exists()) {
    print('❌ Error: assets/reactions directory not found');
    return;
  }

  // Find all folders in reactions directory
  final allFolders = <String>[];
  await for (final entity in reactionsDir.list()) {
    if (entity is Directory) {
      final folderName = entity.path.split(Platform.pathSeparator).last;
      if (folderName != 'emoji') { // Skip emoji folder
        allFolders.add(folderName);
      }
    }
  }

  if (allFolders.isEmpty) {
    print('📁 No reaction folders found (except emoji)');
    return;
  }

  print('📁 Found folders: ${allFolders.join(', ')}\n');

  // Check which folders have content
  final foldersWithContent = <String>[];
  for (final folder in allFolders) {
    final hasContent = await _checkFolderHasContent(folder);
    if (hasContent) {
      foldersWithContent.add(folder);
      print('✅ $folder: Has content');
    } else {
      print('⚠️  $folder: Empty (will be ignored)');
    }
  }

  if (foldersWithContent.isEmpty) {
    print('\n❌ No folders with content found');
    return;
  }

  // Update the reaction picker code
  await _updateReactionPickerCode(foldersWithContent);
  
  print('\n🎉 Done! Restart your app to see the new reaction tabs');
  print('💡 Tip: Add files to folders and run this script again to update');
}

Future<bool> _checkFolderHasContent(String folder) async {
  final folderDir = Directory('assets/reactions/$folder');
  bool hasImages = false;
  
  try {
    await for (final entity in folderDir.list()) {
      if (entity is File) {
        final fileName = entity.path.split(Platform.pathSeparator).last.toLowerCase();
        if (fileName.endsWith('.png') || fileName.endsWith('.svg')) {
          hasImages = true;
          break;
        }
      }
    }
  } catch (e) {
    print('Error checking folder $folder: $e');
  }
  
  return hasImages;
}

Future<void> _updateReactionPickerCode(List<String> folders) async {
  final pickerFile = File('lib/widgets/reactions/reaction_picker.dart');
  
  if (!await pickerFile.exists()) {
    print('❌ Error: reaction_picker.dart not found');
    return;
  }

  String content = await pickerFile.readAsString();
  
  // Find the line with knownFolders
  final knownFoldersPattern = RegExp(r'final knownFolders = \[([^\]]+)\];');
  final match = knownFoldersPattern.firstMatch(content);
  
  if (match == null) {
    print('❌ Error: Could not find knownFolders line in reaction_picker.dart');
    return;
  }

  // Create new folder list as string
  final newFoldersList = folders.map((f) => "'$f'").join(', ');
  
  // Replace the old list with new one
  final newKnownFoldersLine = "final knownFolders = [$newFoldersList];";
  
  content = content.replaceFirst(match.group(0)!, newKnownFoldersLine);
  
  // Write back to file
  await pickerFile.writeAsString(content);
  
  print('📝 Updated reaction_picker.dart with folders: ${folders.join(', ')}');
}
