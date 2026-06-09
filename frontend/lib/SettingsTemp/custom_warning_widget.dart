import 'package:flutter/material.dart';

class CustomWarningWidget {
  // Success message with green theme
  static void showSuccess(BuildContext context, String message) {
    _showCustomMessage(
      context,
      message,
      Icons.check_circle_outline,
      const Color(0xFF10B981),
      const Color(0xFFD1FAE5),
      const Color(0xFF065F46),
    );
  }

  // Error message with red theme
  static void showError(BuildContext context, String message) {
    _showCustomMessage(
      context,
      message,
      Icons.error_outline,
      const Color(0xFFEF4444),
      const Color(0xFFFEE2E2),
      const Color(0xFF991B1B),
    );
  }

  // Warning message with orange theme
  static void showWarning(BuildContext context, String message) {
    _showCustomMessage(
      context,
      message,
      Icons.warning_amber_outlined,
      const Color(0xFFF59E0B),
      const Color(0xFFFEF3C7),
      const Color(0xFF92400E),
    );
  }

  // Info message with blue theme
  static void showInfo(BuildContext context, String message) {
    _showCustomMessage(
      context,
      message,
      Icons.info_outline,
      const Color(0xFF3B82F6),
      const Color(0xFFDBEAFE),
      const Color(0xFF1E40AF),
    );
  }

  // Custom message with specified colors
  static void _showCustomMessage(
    BuildContext context,
    String message,
    IconData icon,
    Color iconColor,
    Color backgroundColor,
    Color textColor,
  ) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: iconColor.withOpacity(0.3), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      color: iconColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => overlayEntry.remove(),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.close,
                        color: iconColor,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // Auto-remove after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  // Animated success message
  static void showAnimatedSuccess(BuildContext context, String message) {
    _showAnimatedMessage(
      context,
      message,
      Icons.check_circle,
      const Color(0xFF10B981),
      const Color(0xFFD1FAE5),
      const Color(0xFF065F46),
    );
  }

  // Animated error message
  static void showAnimatedError(BuildContext context, String message) {
    _showAnimatedMessage(
      context,
      message,
      Icons.error,
      const Color(0xFFEF4444),
      const Color(0xFFFEE2E2),
      const Color(0xFF991B1B),
    );
  }

  // Animated message with slide-in animation
  static void _showAnimatedMessage(
    BuildContext context,
    String message,
    IconData icon,
    Color iconColor,
    Color backgroundColor,
    Color textColor,
  ) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 300),
          tween: Tween(begin: -1.0, end: 0.0),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, value * 100),
              child: Opacity(
                opacity: (1 + value).clamp(0.0, 1.0),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: iconColor.withOpacity(0.3), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: iconColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              icon,
                              color: iconColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => overlayEntry.remove(),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: iconColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(
                                Icons.close,
                                color: iconColor,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // Auto-remove after 4 seconds with slide-out animation
    Future.delayed(const Duration(seconds: 4), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  // Toast-style message (bottom of screen)
  static void showToast(BuildContext context, String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    final iconColor = isError ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    final backgroundColor = isError ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5);
    final textColor = isError ? const Color(0xFF991B1B) : const Color(0xFF065F46);
    final icon = isError ? Icons.error_outline : Icons.check_circle_outline;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: MediaQuery.of(context).padding.bottom + 20,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: iconColor.withOpacity(0.3), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: iconColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // Auto-remove after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }
}
