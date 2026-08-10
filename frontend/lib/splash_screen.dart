import 'package:flutter/material.dart';
import 'widgets/app_colors.dart';
import 'widgets/wave_widget.dart';
import 'dart:async';
import 'utils/responsive.dart';
import 'utils/theme_helper.dart';

class SplashScreen extends StatefulWidget {
  final bool autoNavigate;

  const SplashScreen({super.key, this.autoNavigate = true});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    if (widget.autoNavigate) {
      Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/main');
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          // Top blue wave
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: const DeepTopWaveClipper(),
              child: Container(
                height: MediaQuery.sizeOf(context).height * 0.18,
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          // Bottom blue wave
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipPath(
              clipper: const AltBottomWaveClipper(),
              child: Container(
                height: MediaQuery.sizeOf(context).height * 0.15,
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          // Center icon
          Center(
            child: ScaleTransition(
              scale: _animation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 16,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.white, Colors.green],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/icon.png',
                          width: 140,
                          height: 140,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.cyan),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Loading your workspace...',
                    style: TextStyle(
                      color: AppThemeColors.primaryText(context),
                      fontSize: context.sp(13),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
