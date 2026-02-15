/// Conditional export: web gets the stub, mobile/desktop gets the real package.
export 'ffmpeg_stub.dart' if (dart.library.io) 'ffmpeg_io.dart';
