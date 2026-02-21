// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter_riverpod/flutter_riverpod.dart';

class UploadProgress {
  final double progress;
  final bool isUploading;
  final String? error;

  UploadProgress({this.progress = 0, this.isUploading = false, this.error});
}

class UploadNotifier extends Notifier<UploadProgress> {
  @override
  UploadProgress build() => UploadProgress();

  void setProgress(double progress) {
    state = UploadProgress(progress: progress, isUploading: true);
  }

  void start() {
    state = UploadProgress(progress: 0, isUploading: true);
  }

  void complete() {
    state = UploadProgress(progress: 1, isUploading: false);
    // Reset after success
    Future.delayed(const Duration(seconds: 2), () {
      if (state.progress == 1 && !state.isUploading) {
        state = UploadProgress();
      }
    });
  }

  void fail(String error) {
    state = UploadProgress(progress: 0, isUploading: false, error: error);
  }
}

final uploadProvider = NotifierProvider<UploadNotifier, UploadProgress>(UploadNotifier.new);
