// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../media/signed_media_image.dart';

class ChatBubbleWidget extends StatefulWidget {
  const ChatBubbleWidget({
    super.key,
    required this.message,
    required this.isMe,
    required this.timestamp,
    this.isSending = false,
    this.isDelivered = false,
    this.isRead = false,
    this.decryptionFailed = false,
    this.sendFailed = false,
    this.isFirstInCluster = true,
    this.isLastInCluster = true,
    this.avatarUrl,
    this.avatarInitial,
    this.showAvatar = true,
    this.onLongPress,
    this.onReply,
    this.onDelete,
  });

  final String message;
  final bool isMe;
  final DateTime? timestamp;
  final bool isSending;
  final bool isDelivered;
  final bool isRead;
  final bool decryptionFailed;
  final bool sendFailed;
  final bool isFirstInCluster;
  final bool isLastInCluster;
  final String? avatarUrl;
  final String? avatarInitial;
  final bool showAvatar;
  final VoidCallback? onLongPress;
  final VoidCallback? onReply;
  final VoidCallback? onDelete;

  @override
  State<ChatBubbleWidget> createState() => _ChatBubbleWidgetState();
}

class _ChatBubbleWidgetState extends State<ChatBubbleWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _hovering = false;

  bool get _isDesktop {
    final platform = Theme.of(context).platform;
    return kIsWeb ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fade =
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void didUpdateWidget(covariant ChatBubbleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message != oldWidget.message ||
        widget.timestamp != oldWidget.timestamp) {
      _animController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String get _statusText {
    if (widget.sendFailed) return 'Failed to send';
    if (widget.isSending) return 'Sending...';
    if (widget.timestamp != null) {
      final ts = widget.timestamp!;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tsDay = DateTime(ts.year, ts.month, ts.day);
      if (tsDay == today) {
        return DateFormat.jm().format(ts); // e.g. 2:34 PM
      } else if (today.difference(tsDay).inDays < 7) {
        return DateFormat('E h:mm a').format(ts); // e.g. Mon 2:34 PM
      } else {
        return DateFormat('MMM d, h:mm a').format(ts); // e.g. Feb 14, 2:34 PM
      }
    }
    return '';
  }

  String get _semanticsStatus {
    if (widget.sendFailed) return 'Failed to send';
    if (widget.decryptionFailed) return 'Message failed to decrypt';
    if (widget.isSending) return 'Sending';
    if (widget.isRead) return 'Message read by recipient';
    if (widget.isDelivered) return 'Delivered to recipient';
    return 'Sent';
  }

  String get _semanticsLabel {
    final direction = widget.isMe ? 'Outgoing message' : 'Incoming message';
    return '$direction. $_semanticsStatus. ${widget.message}';
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScaleFactorOf(context);

    return Semantics(
      label: _semanticsLabel,
      container: true,
      child: MouseRegion(
        onEnter: _isDesktop ? (_) => setState(() => _hovering = true) : null,
        onExit: _isDesktop ? (_) => setState(() => _hovering = false) : null,
        child: GestureDetector(
          onLongPress: widget.onLongPress ?? widget.onDelete,
          onSecondaryTap: kIsWeb ? (widget.onLongPress ?? widget.onDelete) : null,
          behavior: HitTestBehavior.translucent,
          child: Align(
            alignment:
                widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double scaleDelta =
                    (textScale - 1).clamp(0.0, 1.0).toDouble();
                final widthFactor = max(0.7, 0.86 - (scaleDelta * 0.1));
                final maxWidth = min(constraints.maxWidth * widthFactor, 520.0);
                final bubble = ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      FadeTransition(
                        opacity: _fade,
                        child: SlideTransition(
                          position: _slide,
                          child: _buildBubbleContent(textScale),
                        ),
                      ),
                      if (_isDesktop) _buildHoverActions(),
                    ],
                  ),
                );

                if (!widget.showAvatar) return bubble;

                // Only show avatar for incoming messages — not for own messages
                if (widget.isMe) return bubble;

                final avatar = _buildAvatar();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    avatar,
                    const SizedBox(width: 10),
                    Flexible(child: bubble),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final background =
        widget.isMe ? AppTheme.navyBlue.withValues(alpha: 0.12) : AppTheme.queenPink;
    final border = widget.isMe ? AppTheme.navyBlue : AppTheme.brightNavy;
    final textColor = widget.isMe ? AppTheme.navyBlue : AppTheme.navyBlue;
    final label = (widget.avatarInitial ?? '?').trim();
    final displayLabel = label.isNotEmpty ? label[0].toUpperCase() : '?';

    if (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SignedMediaImage(
            url: widget.avatarUrl!,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border.withValues(alpha: 0.3), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        displayLabel,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  void _showImageFullscreen(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            child: SignedMediaImage(
              url: url,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubbleContent(double textScale) {
    final background = widget.isMe ? AppTheme.navyBlue : AppTheme.cardSurface;
    final textColor = widget.isMe ? AppTheme.white : AppTheme.navyText;
    final borderColor = widget.isMe
        ? AppTheme.navyBlue.withValues(alpha: 0.35)
        : AppTheme.navyBlue.withValues(alpha: 0.08);

    final parsed = _parseReply(widget.message);
    final attachments = _extractAttachments(parsed?.body ?? widget.message);
    final bodyText = attachments.cleanedText;

    final statusColor = widget.sendFailed
        ? AppTheme.error
        : widget.isMe
            ? SojornColors.basicWhite.withValues(alpha: 0.75)
            : AppTheme.textDisabled;

    final statusIcon = widget.sendFailed
        ? Icons.error_outline
        : widget.isRead
            ? Icons.done_all
            : widget.isDelivered
                ? Icons.done_all
                : Icons.done;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: EdgeInsets.only(
        top: widget.isFirstInCluster ? 12 : 4,
        bottom: widget.isLastInCluster ? 10 : 2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: _bubbleRadius(),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppTheme.navyBlue.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (parsed != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: SojornColors.basicWhite.withValues(alpha: widget.isMe ? 0.08 : 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.isMe
                      ? SojornColors.basicWhite.withValues(alpha: 0.12)
                      : AppTheme.navyBlue.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parsed.replyLabel,
                    style: GoogleFonts.inter(
                      color:
                          widget.isMe ? SojornColors.basicWhite.withValues(alpha: 0.7) : AppTheme.navyBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    textScaleFactor: textScale,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    parsed.replySnippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: widget.isMe
                          ? SojornColors.basicWhite.withValues(alpha: 0.7)
                          : AppTheme.textDisabled,
                      fontSize: 13,
                    ),
                    textScaleFactor: textScale,
                  ),
                ],
              ),
            ),
          ],
          if (widget.decryptionFailed)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_reset,
                  size: 16,
                  color: widget.isMe ? SojornColors.basicWhite.withValues(alpha: 0.7) : AppTheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Unable to decrypt',
                    style: GoogleFonts.inter(
                      color: widget.isMe ? SojornColors.basicWhite.withValues(alpha: 0.7) : AppTheme.error,
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                    ),
                    textScaleFactor: textScale,
                  ),
                ),
              ],
            )
          else ...[
            if (bodyText.isNotEmpty)
              Text(
                bodyText,
                textAlign: TextAlign.left,
                style: GoogleFonts.inter(
                  color: textColor,
                  fontSize: 15,
                  height: 1.35,
                ),
                textScaleFactor: textScale,
              ),
            if (attachments.images.isNotEmpty || attachments.videos.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  ...attachments.images.map(
                    (url) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 4 / 5, // portrait cap — never taller than 4:5
                          child: GestureDetector(
                            onTap: () => _showImageFullscreen(context, url),
                            child: SignedMediaImage(
                              url: url,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ...attachments.videos.map(
                    (url) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _VideoAttachment(url: url, isMine: widget.isMe),
                    ),
                  ),
                ],
              ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                _statusText,
                style: GoogleFonts.inter(
                  color: statusColor,
                  fontSize: 11,
                ),
                textScaleFactor: textScale,
              ),
              const SizedBox(width: 6),
              if (widget.isMe)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: widget.isSending
                      ? SizedBox(
                          key: const ValueKey('sending'),
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(statusColor),
                          ),
                        )
                      : Icon(
                          key: ValueKey(statusIcon),
                          statusIcon,
                          size: 14,
                          color: widget.sendFailed
                              ? AppTheme.error
                              : widget.isRead
                                  ? SojornColors.basicWhite
                                  : statusColor,
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  BorderRadius _bubbleRadius() {
    const tight = Radius.circular(8);
    const loose = Radius.circular(18);

    if (widget.isMe) {
      return BorderRadius.only(
        topLeft: loose,
        topRight: widget.isFirstInCluster ? loose : tight,
        bottomLeft: widget.isLastInCluster ? loose : tight,
        bottomRight: tight,
      );
    }

    return BorderRadius.only(
      topLeft: tight,
      topRight: loose,
      bottomLeft: tight,
      bottomRight: widget.isLastInCluster ? loose : tight,
    );
  }

  Widget _buildHoverActions() {
    final actions = <Widget>[];
    if (widget.onReply != null) {
      actions.add(
        IconButton(
          splashRadius: 18,
          tooltip: 'Reply',
          icon: const Icon(Icons.reply_outlined, size: 18),
          color: AppTheme.navyBlue,
          onPressed: widget.onReply,
        ),
      );
    }
    if (widget.onDelete != null) {
      actions.add(
        IconButton(
          splashRadius: 18,
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline, size: 18),
          color: AppTheme.error,
          onPressed: widget.onDelete,
        ),
      );
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: -6,
      right: widget.isMe ? 4 : null,
      left: widget.isMe ? null : 4,
      child: AnimatedOpacity(
        opacity: _hovering ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.cardSurface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: SojornColors.overlayScrim,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: actions,
          ),
        ),
      ),
    );
  }

  _ReplyParts? _parseReply(String text) {
    final lines = text.split('\n');
    if (lines.length < 2) return null;
    final first = lines.first.trim();
    if (!first.toLowerCase().startsWith('replying to')) return null;
    final label =
        first.replaceFirst(RegExp('replying to', caseSensitive: false), '').trim();
    final body = lines.sublist(1).join('\n').trim();
    if (label.isEmpty || body.isEmpty) return null;
    final snippet = body.length > 120 ? '${body.substring(0, 120)}…' : body;
    return _ReplyParts(replyLabel: label, replySnippet: snippet, body: body);
  }
}

class _ReplyParts {
  final String replyLabel;
  final String replySnippet;
  final String body;

  _ReplyParts({
    required this.replyLabel,
    required this.replySnippet,
    required this.body,
  });
}

class _AttachmentParseResult {
  final List<String> images;
  final List<String> videos;
  final String cleanedText;

  _AttachmentParseResult({
    required this.images,
    required this.videos,
    required this.cleanedText,
  });
}

_AttachmentParseResult _extractAttachments(String text) {
  final lines = text.split('\n');
  final images = <String>[];
  final videos = <String>[];
  final kept = <String>[];

  final imgPattern = RegExp(r'^\[img\](.+)$');
  final vidPattern = RegExp(r'^\[video\](.+)$');

  for (final line in lines) {
    final trimmed = line.trim();
    final imgMatch = imgPattern.firstMatch(trimmed);
    final vidMatch = vidPattern.firstMatch(trimmed);
    if (imgMatch != null) {
      images.add(imgMatch.group(1)!.trim());
      continue;
    }
    if (vidMatch != null) {
      videos.add(vidMatch.group(1)!.trim());
      continue;
    }
    if (trimmed.isNotEmpty) {
      kept.add(trimmed);
    }
  }

  return _AttachmentParseResult(
    images: images,
    videos: videos,
    cleanedText: kept.join('\n').trim(),
  );
}

class _VideoAttachment extends StatelessWidget {
  final String url;
  final bool isMine;

  const _VideoAttachment({required this.url, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isMine ? SojornColors.basicWhite.withValues(alpha: 0.08) : AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMine
              ? SojornColors.basicWhite.withValues(alpha: 0.2)
              : AppTheme.navyBlue.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        leading: Icon(Icons.videocam, color: isMine ? SojornColors.basicWhite : AppTheme.navyBlue),
        title: Text(
          'Video attachment',
          style: GoogleFonts.inter(
            color: isMine ? SojornColors.basicWhite : AppTheme.navyText,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: isMine ? SojornColors.basicWhite.withValues(alpha: 0.7) : AppTheme.textDisabled,
            fontSize: 12,
          ),
        ),
        trailing: Icon(Icons.open_in_new,
            color: isMine ? SojornColors.basicWhite.withValues(alpha: 0.7) : AppTheme.navyBlue),
        onTap: () async {
          // Fallback: open in browser
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        },
      ),
    );
  }
}
