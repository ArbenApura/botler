// THE HEALTH HOME SCREEN: ONE SMALL PICTURE FOR EACH PART OF HEALTH, THE WEEKLY CHECK-IN WHEN ONE IS OPEN, AND ONE PRIMARY ACTION, LOG FOOD.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/health.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'health_parts.dart';
import 'home_tiles.dart';

// -- TYPES -- //

class HealthHomeScreen extends ConsumerWidget {
  const HealthHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final home = ref.watch(healthHomeProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.healthTitle)),
      body: AsyncBody<Json>(
        value: home,
        onRetry: () => ref.invalidate(healthHomeProvider),
        skeleton: const SkeletonPage(
          child: SkeletonRows(count: 4, kind: SkeletonKind.tile),
        ),
        data: (h) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(healthHomeProvider),
          child: ListView(
            padding: pagePadding(context),
            children: <Widget>[
              if (h['setupDone'] != true) ...<Widget>[
                SoftCard(
                  onTap: () => context.push('/health/setup'),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.flag_outlined, color: c.accentText),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              t.healthSetupPrompt,
                              style: TextStyle(
                                color: c.accentText,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              t.healthSetupPromptLine,
                              style: TextStyle(
                                color: c.accentText,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: c.accentText),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              HomeTiles(home: h),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomDock(
        showAsk: true,
        primary: FilledButton.icon(
          onPressed: () => context.push('/health/camera?mode=meal'),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(t.healthLogFood),
        ),
      ),
    );
  }
}
