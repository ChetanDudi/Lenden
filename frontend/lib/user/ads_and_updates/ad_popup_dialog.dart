import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../utils/api_client.dart';
import '../digitise/subscriptions_page.dart';

class UserAdPopupDialog extends StatefulWidget {
  final Map<String, dynamic> ad;

  const UserAdPopupDialog({super.key, required this.ad});

  @override
  State<UserAdPopupDialog> createState() => _UserAdPopupDialogState();
}

class _UserAdPopupDialogState extends State<UserAdPopupDialog> {
  bool _videoCanClose = false;
  bool _impressionTracked = false;

  @override
  void initState() {
    super.initState();
    unawaited(_trackAdEvent('impression'));
  }

  Future<void> _trackAdEvent(String type, {int watchSeconds = 0}) async {
    await _trackAdEventWithMetadata(type, watchSeconds: watchSeconds);
  }

  Future<void> _trackAdEventWithMetadata(
    String type, {
    int watchSeconds = 0,
    Map<String, dynamic>? metadata,
  }) async {
    final adId = widget.ad['_id']?.toString();
    if (adId == null || adId.isEmpty) return;
    if (type == 'impression' && _impressionTracked) return;
    try {
      await ApiClient.post(
        '/api/ads/$adId/events',
        body: {
          'type': type,
          'watchSeconds': watchSeconds,
          'metadata': {
            'mediaKind': (widget.ad['mediaKind'] ?? 'none').toString(),
            ...?metadata,
          },
        },
      );
      if (type == 'impression') {
        _impressionTracked = true;
      }
    } catch (_) {}
  }

  int _watchSeconds() =>
      int.tryParse((widget.ad['_watchSeconds'] ?? '0').toString()) ?? 0;

  void _closeAd(BuildContext context, {String eventType = 'close'}) {
    unawaited(_trackAdEvent(eventType, watchSeconds: _watchSeconds()));
    Navigator.of(context).pop();
  }

  Future<void> _reportAd(BuildContext context) async {
    final controller = TextEditingController();
    final shouldReport = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Report This Ad',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tell us what feels wrong about this ad. This helps admins review and improve what users see.',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    hintText: 'Example: irrelevant, repeated too often, misleading',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                        ),
                        child: const Text('Report'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (shouldReport != true || !mounted) return;

    final adId = widget.ad['_id']?.toString();
    if (adId == null || adId.isEmpty) return;

    try {
      await ApiClient.post(
        '/api/ads/$adId/events',
        body: {
          'type': 'report',
          'watchSeconds': _watchSeconds(),
          'metadata': {
            'mediaKind': (widget.ad['mediaKind'] ?? 'none').toString(),
            'reason': controller.text.trim(),
          },
        },
      );
      if (!mounted) return;
      showSnack(context, 'Ad reported. Thanks for the feedback.');
    } catch (_) {
      if (!mounted) return;
      showSnack(context, 'Could not report this ad right now.', isError: true);
    }
  }

  Future<void> _hideForAWeek(BuildContext context) async {
    final controller = TextEditingController();
    final shouldHide = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Not Interested',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  'We can hide this ad from your screen for a week. You can optionally tell us why.',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Optional reason',
                    hintText: 'Example: not relevant to me',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                        ),
                        child: const Text('Hide 7 Days'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (shouldHide != true || !mounted) return;

    try {
      await _trackAdEventWithMetadata(
        'hide',
        watchSeconds: _watchSeconds(),
        metadata: {
          'hideMode': 'week',
          'reason': controller.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(context, 'This ad will stay hidden for 7 days.');
    } catch (_) {
      if (!mounted) return;
      showSnack(context, 'Could not hide this ad right now.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    final mediaKind = (ad['mediaKind'] ?? 'none').toString();
    final mediaUrl = (ad['mediaUrl'] ?? '').toString();
    final ctaText = (ad['callToActionText'] ?? '').toString();
    final ctaUrl = (ad['callToActionUrl'] ?? '').toString();
    final allowImmediateClose = mediaKind != 'video';
    final videoCloseAtPercent =
        int.tryParse((ad['videoCloseAtPercent'] ?? '100').toString()) ?? 100;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [AppColors.cyan, Color(0xFF0077B6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gradient header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF0077B6)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'Sponsored',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const Spacer(),
                        _buildOptionsMenu(context),
                        const SizedBox(width: 4),
                        if (allowImmediateClose || _videoCanClose)
                          _buildCloseButton(context)
                        else
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.lock_outline,
                                color: Colors.white, size: 20),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      allowImmediateClose
                          ? 'You can close this ad anytime.'
                          : 'Close unlocks after ${_closeUnlockLabel(videoCloseAtPercent)}.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Content area
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((ad['title'] ?? '').toString().trim().isNotEmpty)
                      Text(
                        ad['title'].toString(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    if ((ad['body'] ?? '').toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        ad['body'].toString(),
                        style: const TextStyle(height: 1.45),
                      ),
                    ],
                    if (mediaKind != 'none' && mediaUrl.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: mediaKind == 'video'
                            ? _AdVideoPlayer(
                                url: mediaUrl,
                                closeAtPercent: videoCloseAtPercent,
                                onCloseUnlocked: () {
                                  if (!mounted || _videoCanClose) return;
                                  setState(() => _videoCanClose = true);
                                },
                                onWatchSecondsChanged: (seconds) {
                                  widget.ad['_watchSeconds'] = seconds;
                                },
                              )
                            : Image.network(
                                mediaUrl,
                                height: 210,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ],
                    if (ctaText.trim().isNotEmpty &&
                        ctaUrl.trim().isNotEmpty) ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final uri = Uri.tryParse(ctaUrl);
                            if (uri != null) {
                              await _trackAdEvent('click',
                                  watchSeconds: _watchSeconds());
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(ctaText),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionsMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 4,
      onSelected: (value) {
        switch (value) {
          case 'hide_today':
            unawaited(_trackAdEventWithMetadata(
              'hide',
              watchSeconds: _watchSeconds(),
              metadata: const {'hideMode': 'today'},
            ));
            Navigator.of(context).pop();
          case 'not_interested':
            _hideForAWeek(context);
          case 'report':
            _reportAd(context);
          case 'subscribe':
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SubscriptionsPage()),
            );
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'hide_today',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.visibility_off_outlined, size: 20),
            title: Text('Hide Today', style: TextStyle(fontSize: 14)),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'not_interested',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.thumb_down_outlined, size: 20),
            title: Text('Not Interested', style: TextStyle(fontSize: 14)),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'report',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.flag_outlined, size: 20),
            title: Text('Report Ad', style: TextStyle(fontSize: 14)),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'subscribe',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.workspace_premium_outlined,
                size: 20, color: Color(0xFF0077B6)),
            title: Text(
              'Subscribe',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF0077B6),
                fontWeight: FontWeight.w700,
              ),
            ),
            dense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.close, color: Colors.white),
      onPressed: () => _closeAd(context),
    );
  }

  String _closeUnlockLabel(int percent) {
    switch (percent) {
      case 25:
        return '25% of the video has played';
      case 50:
        return '50% of the video has played';
      case 75:
        return '75% of the video has played';
      default:
        return 'the video ends';
    }
  }
}

class _AdVideoPlayer extends StatefulWidget {
  final String url;
  final int closeAtPercent;
  final VoidCallback onCloseUnlocked;
  final ValueChanged<int>? onWatchSecondsChanged;

  const _AdVideoPlayer({
    required this.url,
    required this.closeAtPercent,
    required this.onCloseUnlocked,
    this.onWatchSecondsChanged,
  });

  @override
  State<_AdVideoPlayer> createState() => _AdVideoPlayerState();
}

class _AdVideoPlayerState extends State<_AdVideoPlayer> {
  VideoPlayerController? _controller;
  Timer? _refreshTimer;
  Timer? _loadingCountdownTimer;
  bool _ready = false;
  bool _closeUnlocked = false;
  bool _loadFailed = false;
  late int _fallbackUnlockSeconds;

  @override
  void initState() {
    super.initState();
    _fallbackUnlockSeconds = _fallbackSecondsFor(widget.closeAtPercent);
    _loadingCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _ready || _closeUnlocked) return;
      if (_fallbackUnlockSeconds > 0) {
        setState(() => _fallbackUnlockSeconds -= 1);
      }
      if (_fallbackUnlockSeconds <= 0) {
        _unlockClose();
      }
    });
    _initController();
  }

  void _initController() {
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = ctrl;
    ctrl.initialize().then((_) {
      if (!mounted || _controller != ctrl) return;
      setState(() {
        _ready = true;
        _loadFailed = false;
      });
      ctrl
        ..setLooping(true)
        ..play();
      _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !ctrl.value.isInitialized) return;
        _checkCloseUnlock();
        widget.onWatchSecondsChanged?.call(
          ctrl.value.position.inSeconds.clamp(0, 86400),
        );
        setState(() {});
      });
    }).catchError((error) {
      debugPrint('AdVideoPlayer: initialize() failed: $error');
      if (!mounted || _controller != ctrl) return;
      setState(() => _loadFailed = true);
    });
  }

  Future<void> _retry() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final old = _controller;
    _controller = null;
    setState(() {
      _ready = false;
      _loadFailed = false;
      _fallbackUnlockSeconds = _fallbackSecondsFor(widget.closeAtPercent);
    });
    await old?.dispose();
    if (!mounted) return;
    _initController();
  }

  int _fallbackSecondsFor(int closeAtPercent) {
    switch (closeAtPercent) {
      case 25:
        return 16;
      case 50:
        return 24;
      case 75:
        return 32;
      default:
        return 45;
    }
  }

  void _unlockClose() {
    if (_closeUnlocked) return;
    _closeUnlocked = true;
    widget.onCloseUnlocked();
  }

  void _checkCloseUnlock() {
    if (_closeUnlocked) return;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final duration = ctrl.value.duration;
    final position = ctrl.value.position;
    if (duration.inMilliseconds <= 0) return;
    final unlockAtMs =
        (duration.inMilliseconds * widget.closeAtPercent / 100).round();
    if (position.inMilliseconds >= unlockAtMs) {
      _unlockClose();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _loadingCountdownTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Container(
        height: 210,
        color: Colors.black12,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loadFailed) ...[
                    const Icon(Icons.videocam_off_outlined,
                        size: 40, color: Colors.black45),
                    const SizedBox(height: 10),
                    const Text(
                      'Video failed to load.',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                    ),
                  ] else ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    const Text(
                      'Loading video...',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _closeUnlocked
                        ? 'You can close this ad now.'
                        : 'Close unlocks in ${_fallbackUnlockSeconds.clamp(0, 999)}s.',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _closeUnlocked
                      ? '0s'
                      : '${_fallbackUnlockSeconds.clamp(0, 999)}s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final ctrl = _controller!;
    final duration = ctrl.value.duration;
    final position = ctrl.value.position;
    final totalSeconds = duration.inSeconds > 0 ? duration.inSeconds : 0;
    final remainingSeconds =
        (duration - position).inSeconds.clamp(0, totalSeconds);
    final unlockAtMs =
        (duration.inMilliseconds * widget.closeAtPercent / 100).round();
    final closeRemainingSeconds =
        ((unlockAtMs - position.inMilliseconds) / 1000).ceil().clamp(0, totalSeconds);

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        AspectRatio(
          aspectRatio: ctrl.value.aspectRatio,
          child: VideoPlayer(ctrl),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '${remainingSeconds}s',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _closeUnlocked
                  ? 'Close button is now available.'
                  : widget.closeAtPercent == 100
                      ? 'Close will appear after the video finishes.'
                      : 'Close unlocks in ${closeRemainingSeconds}s.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
