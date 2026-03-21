import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── 아이콘 + 타이틀 ────────────────────────────────────
                  Icon(Icons.precision_manufacturing_rounded,
                      size: 96, color: cs.primary),
                  const SizedBox(height: 20),
                  Text(
                    'Robotics Tool',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select a mode to get started',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 48),

                  // ── Topic Monitor 카드 ─────────────────────────────────
                  _ModeCard(
                    icon: Icons.monitor_heart_outlined,
                    title: 'Topic Monitor',
                    subtitle: 'ROS2 토픽 모니터링, 시각화, publish',
                    color: cs.primaryContainer,
                    onColor: cs.onPrimaryContainer,
                    onTap: () =>
                        Navigator.pushNamed(context, '/connection'),
                  ),
                  const SizedBox(height: 16),

                  // ── Model Viewer 카드 ──────────────────────────────────
                  _ModeCard(
                    icon: Icons.view_in_ar_rounded,
                    title: 'Model Viewer',
                    subtitle: 'STL / URDF 3D 모델 뷰어',
                    color: cs.tertiaryContainer,
                    onColor: cs.onTertiaryContainer,
                    onTap: () => Navigator.pushNamed(context, '/model'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            children: [
              Icon(icon, size: 48, color: onColor),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                                color: onColor, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: onColor.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: onColor),
            ],
          ),
        ),
      ),
    );
  }
}
