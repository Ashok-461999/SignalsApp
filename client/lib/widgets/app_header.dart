import 'package:flutter/material.dart';

import '../theme/app_branding.dart';
import '../theme/app_theme.dart';

/// Compact top bar — Indian markets only.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;

    return Material(
      color: AppColors.surface.withValues(alpha: 0.98),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.98),
          border: Border(
            bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
              ),
              child: const Icon(Icons.auto_graph_rounded, color: AppColors.accent, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppBranding.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'NSE · BSE · F&O options',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
