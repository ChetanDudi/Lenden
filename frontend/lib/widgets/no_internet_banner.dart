import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/connectivity_service.dart';
import '../l10n/app_localizations.dart';

class NoInternetBanner extends StatefulWidget {
  final Widget child;
  const NoInternetBanner({super.key, required this.child});

  @override
  State<NoInternetBanner> createState() => _NoInternetBannerState();
}

class _NoInternetBannerState extends State<NoInternetBanner> {
  final _service = ConnectivityService();
  StreamSubscription<bool>? _sub;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _offline = !_service.isOnline;
    _sub = _service.onStatusChange.listen((online) {
      if (mounted) setState(() => _offline = !online);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _offline ? 36 : 0,
          color: Colors.red.shade700,
          child: _offline
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      t('no_internet_title'),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
