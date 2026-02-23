// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../../models/sojorn_media_result.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';

class sojornImageEditor extends StatelessWidget {
  final String? imagePath;
  final Uint8List? imageBytes;
  final String? imageName;
  final bool isBeacon;
  final String? postType;

  const sojornImageEditor({
    super.key,
    this.imagePath,
    this.imageBytes,
    this.imageName,
    this.isBeacon = false,
    this.postType,
  }) : assert(imagePath != null || imageBytes != null);

  static const Color _matteBlack = Color(0xFF0B0B0B);
  static const Color _panelBlack = Color(0xFF111111);

  ThemeData _buildEditorTheme() {
    final baseTheme = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(baseTheme.textTheme).apply(
      bodyColor: SojornColors.basicWhite,
      displayColor: SojornColors.basicWhite,
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: _matteBlack,
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: AppTheme.brightNavy,
        secondary: AppTheme.brightNavy,
        surface: _matteBlack,
        onSurface: SojornColors.basicWhite,
      ),
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: SojornColors.basicWhite),
      appBarTheme: const AppBarTheme(
        backgroundColor: _matteBlack,
        foregroundColor: SojornColors.basicWhite,
        elevation: 0,
      ),
      sliderTheme: baseTheme.sliderTheme.copyWith(
        activeTrackColor: AppTheme.brightNavy,
        inactiveTrackColor: SojornColors.basicWhite.withValues(alpha: 0.24),
        thumbColor: AppTheme.brightNavy,
        overlayColor: AppTheme.brightNavy.withValues(alpha: 0.2),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.brightNavy,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  ProImageEditorConfigs _buildConfigs() {
    return ProImageEditorConfigs(
      theme: _buildEditorTheme(),
      cropRotateEditor: const CropRotateEditorConfigs(
        initAspectRatio: -1,
        aspectRatios: [
          AspectRatioItem(text: 'Free', value: -1),
          AspectRatioItem(text: '4:5', value: 4 / 5),
          AspectRatioItem(text: '1:1', value: 1),
          AspectRatioItem(text: '3:4', value: 3 / 4),
          AspectRatioItem(text: '9:16', value: 9 / 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageBytes != null) {
      return _buildEditor(context, imageBytes!);
    }

    if (kIsWeb) {
      return _buildError('Failed to load image');
    }

    return FutureBuilder<Uint8List>(
      future: _loadBytes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoading();
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _buildError('Failed to load image');
        }

        return _buildEditor(context, snapshot.data!);
      },
    );
  }

  Future<Uint8List> _loadBytes() async {
    if (imageBytes != null) return imageBytes!;
    return File(imagePath!).readAsBytes();
  }

  Widget _buildEditor(BuildContext context, Uint8List bytes) {
    return ProImageEditor.memory(
      bytes,
      configs: _buildConfigs(),
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (Uint8List editedBytes) async {
          if (!context.mounted) return;
          
          // For web, return bytes directly
          if (kIsWeb) {
            Navigator.pop(
              context,
              SojornMediaResult.image(
                bytes: editedBytes,
                name: imageName ?? 'sojorn_edit.jpg',
              ),
            );
            return;
          }

          // For mobile/desktop, save to temp directory
          try {
            final tempDir = await getTemporaryDirectory();
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final fileName = 'sojorn_image_$timestamp.jpg';
            final file = File('${tempDir.path}/$fileName');
            await file.writeAsBytes(editedBytes);
            
            // Generate dual outputs for beacons
            if (isBeacon) {
              final thumbnailFileName = 'sojorn_thumb_$timestamp.jpg';
              final thumbnailFile = File('${tempDir.path}/$thumbnailFileName');
              
              // Create 300x300 thumbnail
              await _createThumbnail(editedBytes, thumbnailFile);
              
              if (!context.mounted) return;
              Navigator.pop(
                context,
                SojornMediaResult.beaconImage(
                  filePath: file.path,
                  thumbnailPath: thumbnailFile.path,
                  name: fileName,
                ),
              );
            } else {
              if (!context.mounted) return;
              Navigator.pop(
                context,
                SojornMediaResult.image(
                  filePath: file.path,
                  name: fileName,
                ),
              );
            }
          } catch (e) {
            if (!context.mounted) return;
            Navigator.pop(
              context,
              SojornMediaResult.image(
                bytes: editedBytes,
                name: imageName ?? 'sojorn_edit.jpg',
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _createThumbnail(Uint8List originalBytes, File thumbnailFile) async {
    // This is a placeholder for thumbnail generation
    // In a real implementation, you would use an image processing library
    // like 'image' package to resize the image to 300x300
    try {
      // For now, just write the original bytes as a placeholder
      await thumbnailFile.writeAsBytes(originalBytes);
      
      // TODO: Implement proper thumbnail generation using image package
      // Example (requires adding 'image' package to pubspec.yaml):
      // import 'package:image/image.dart' as img;
      // 
      // final image = img.decodeImage(originalBytes)!;
      // final thumbnail = img.copyResize(image, width: 300, height: 300);
      // await thumbnailFile.writeAsBytes(img.encodeJpg(thumbnail, quality: 85));
    } catch (e) {
      // Fallback to original bytes if thumbnail generation fails
      await thumbnailFile.writeAsBytes(originalBytes);
    }
  }

  Widget _buildLoading() {
    return Scaffold(
      backgroundColor: _matteBlack,
      body: Center(
        child: CircularProgressIndicator(
          color: AppTheme.brightNavy,
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Scaffold(
      backgroundColor: _matteBlack,
      body: Center(
        child: Text(
          message,
          style: const TextStyle(color: SojornColors.basicWhite),
        ),
      ),
    );
  }
}
