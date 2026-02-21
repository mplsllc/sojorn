// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

/// Conditional export: web gets the stub, mobile/desktop gets the real package.
export 'ffmpeg_stub.dart' if (dart.library.io) 'ffmpeg_io.dart';
