import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum LandaToastType { success, error, info }

/// Modern, floating top banner notification for Landa OS
/// Replaces standard ScaffoldMessenger with overlay toasts
class LandaToast {
  static void show(
    BuildContext context, {
    required String message,
    LandaToastType type = LandaToastType.success,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        return _LandaToastWidget(
          message: message,
          type: type,
          onDismiss: () {
            if (entry.mounted) {
              entry.remove();
            }
          },
        );
      },
    );

    overlay.insert(entry);

    Future.delayed(duration, () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }

  static void success(BuildContext context, String message) {
    show(context, message: message, type: LandaToastType.success);
  }

  static void error(BuildContext context, String message) {
    show(context, message: message, type: LandaToastType.error);
  }

  static void info(BuildContext context, String message) {
    show(context, message: message, type: LandaToastType.info);
  }
}

class _LandaToastWidget extends StatefulWidget {
  final String message;
  final LandaToastType type;
  final VoidCallback onDismiss;

  const _LandaToastWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_LandaToastWidget> createState() => _LandaToastWidgetState();
}

class _LandaToastWidgetState extends State<_LandaToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData get _icon {
    switch (widget.type) {
      case LandaToastType.success:
        return Icons.check_circle_rounded;
      case LandaToastType.error:
        return Icons.error_outline_rounded;
      case LandaToastType.info:
        return Icons.info_outline_rounded;
    }
  }

  Color get _iconColor {
    switch (widget.type) {
      case LandaToastType.success:
        return AppTheme.successColor;
      case LandaToastType.error:
        return AppTheme.logoutColor;
      case LandaToastType.info:
        return AppTheme.profileColor;
    }
  }

  Color get _backgroundColor {
    switch (widget.type) {
      case LandaToastType.success:
        return AppTheme.successSurfaceColor;
      case LandaToastType.error:
        return AppTheme.logoutSurfaceColor;
      case LandaToastType.info:
        return AppTheme.slateSurfaceColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 16.0, left: 20.0, right: 20.0),
          child: SlideTransition(
            position: _slideAnim,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: _backgroundColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _iconColor.withOpacity(0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(
                      color: _iconColor.withOpacity(0.45),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_icon, color: _iconColor, size: 22),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: _iconColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: widget.onDismiss,
                        child: Icon(
                          Icons.close,
                          color: _iconColor.withOpacity(0.7),
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
