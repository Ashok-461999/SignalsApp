import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Stable full-screen background — no blur, minimal repaint.
class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    required this.child,
    this.showImage = true,
  });

  final Widget child;
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF070B11),
              Color(0xFF0A0F16),
              Color(0xFF0C121A),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showImage)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.14,
                  child: Image.asset(
                    'assets/images/bg_trading_ai.png',
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0.35),
                      AppColors.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Signature AlphaPulse surface — flat panel with left accent bar (no asymmetric border paint).
class AlphaSurface extends StatelessWidget {
  const AlphaSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.accent = AppColors.accent,
    this.borderRadius = 16,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color accent;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final panel = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.96),
        borderRadius: radius,
        border: Border.all(color: AppColors.border.withValues(alpha: 0.75)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: accent),
            Expanded(
              child: Padding(
                padding: padding ?? EdgeInsets.zero,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return panel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: AppColors.accent.withValues(alpha: 0.08),
        highlightColor: AppColors.accent.withValues(alpha: 0.04),
        child: panel,
      ),
    );
  }
}

/// @deprecated Use [AlphaSurface] — kept for any existing imports.
typedef GlassPanel = AlphaSurface;
