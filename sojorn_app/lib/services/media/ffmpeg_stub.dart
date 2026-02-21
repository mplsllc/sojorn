// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

/// Web-safe stubs that mirror the ffmpeg_kit_flutter_new API surface.
/// These classes compile on web but always return failure / no-op.

class FFmpegKit {
  static Future<FFmpegSession> execute(String command) async {
    return FFmpegSession._();
  }

  static Future<FFmpegSession> executeAsync(
    String command, [
    Function? completeCallback,
    Function? logCallback,
    Function? statisticsCallback,
  ]) async {
    final session = FFmpegSession._();
    completeCallback?.call(session);
    return session;
  }

  static Future<FFmpegSession> executeWithArguments(
    List<String> arguments, [
    Function? completeCallback,
    Function? logCallback,
    Function? statisticsCallback,
  ]) async {
    final session = FFmpegSession._();
    completeCallback?.call(session);
    return session;
  }
}

class FFmpegSession {
  FFmpegSession._();

  Future<ReturnCode?> getReturnCode() async => ReturnCode._(-1);
  Future<String?> getOutput() async => null;
  Future<String?> getAllLogsAsString() async => null;
}

class ReturnCode {
  final int _value;
  ReturnCode._(this._value);

  static bool isSuccess(ReturnCode? code) => false;

  @override
  String toString() => 'ReturnCode($_value)';
}
