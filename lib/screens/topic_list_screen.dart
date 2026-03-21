import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/topic_provider.dart';
import '../widgets/settings_button.dart';
import '../widgets/topic_action_bottom_sheet.dart';

class TopicListScreen extends StatelessWidget {
  const TopicListScreen({super.key});

  static const _families = [
    'sensor_msgs',
    'nav_msgs',
    'geometry_msgs',
    'std_msgs',
    'other',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Topics'),
        actions: [
          Consumer<TopicProvider>(
            builder: (_, tp, _) => IconButton(
              onPressed: tp.isLoading ? null : tp.loadTopics,
              icon: tp.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ),
          const SettingsButton(),
        ],
      ),
      body: Column(
        children: [
          _SearchBar(),
          _FilterChips(),
          const Expanded(child: _TopicList()),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tp = context.read<TopicProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SearchBar(
        hintText: 'Search topics…',
        leading: const Icon(Icons.search),
        onChanged: tp.setSearchQuery,
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  static const _families = TopicListScreen._families;

  @override
  Widget build(BuildContext context) {
    return Consumer<TopicProvider>(
      builder: (_, tp, _) => SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _families.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final f = _families[i];
            final selected = tp.typeFilters.contains(f);
            return FilterChip(
              label: Text(f),
              selected: selected,
              onSelected: (_) => tp.toggleTypeFilter(f),
            );
          },
        ),
      ),
    );
  }
}

class _TopicList extends StatelessWidget {
  const _TopicList();

  @override
  Widget build(BuildContext context) {
    return Consumer<TopicProvider>(
      builder: (context, tp, _) {
        if (tp.isLoading && tp.topics.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (tp.error != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 8),
                Text(tp.error!),
                const SizedBox(height: 16),
                FilledButton(onPressed: tp.loadTopics, child: const Text('Retry')),
              ],
            ),
          );
        }

        final topics = tp.filteredTopics;
        if (topics.isEmpty) {
          return const Center(child: Text('No topics found'));
        }

        return ListView.separated(
          itemCount: topics.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final topic = topics[i];
            return ListTile(
              title: Text(topic.name),
              subtitle: Text(topic.type),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showModalBottomSheet(
                context: context,
                builder: (_) => TopicActionBottomSheet(topic: topic),
              ),
            );
          },
        );
      },
    );
  }
}
