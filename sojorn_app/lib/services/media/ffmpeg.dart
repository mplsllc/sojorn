// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

/// Conditional export: web gets the stub, mobile/desktop gets the real package.
export 'ffmpeg_stub.dart' if (dart.library.io) 'ffmpeg_io.dart';
