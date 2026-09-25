import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/topic_provider.dart';
import '../widgets/settings_button.dart';
import '../widgets/topic_action_bottom_sheet.dart';
import '../widgets/topic_icon.dart';
import '../widgets/visualizations/visualizer_registry.dart';

class TopicListScreen extends StatelessWidget {
  const TopicListScreen({super.key});

  static const families = [
    'sensor_msgs',
    'nav_msgs',
    'geometry_msgs',
    'std_msgs',
    'other',
  ];

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Topics'),
            if (conn.connectedIp != null)
              Text('${conn.connectedIp}:${conn.connectedPort}',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
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
      body: const Column(
        children: [
          _SearchBar(),
          _FilterChips(),
          Expanded(child: _TopicList()),
        ],
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar();

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.read<TopicProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SearchBar(
        controller: _controller,
        hintText: 'Search topics or types…',
        leading: const Icon(Icons.search),
        elevation: const WidgetStatePropertyAll(0),
        onChanged: (q) {
          tp.setSearchQuery(q);
          setState(() {});
        },
        trailing: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                tp.setSearchQuery('');
                setState(() {});
              },
            ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context) {
    return Consumer<TopicProvider>(
      builder: (_, tp, _) {
        final counts = tp.familyCounts;
        final shown = TopicListScreen.families.where((f) => (counts[f] ?? 0) > 0).toList();
        return SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final f = shown[i];
              return FilterChip(
                label: Text('$f ${counts[f]}'),
                selected: tp.typeFilters.contains(f),
                onSelected: (_) => tp.toggleTypeFilter(f),
              );
            },
          ),
        );
      },
    );
  }
}

class _TopicList extends StatelessWidget {
  const _TopicList();

  @override
  Widget build(BuildContext context) {
    return Consumer<TopicProvider>(
      builder: (context, tp, _) {
        final cs = Theme.of(context).colorScheme;
        if (tp.isLoading && tp.topics.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (tp.error != null && tp.topics.isEmpty) {
          return _Message(
            icon: Icons.error_outline,
            color: cs.error,
            text: 'Could not load topics\n${tp.error}',
            action: FilledButton(onPressed: tp.loadTopics, child: const Text('Retry')),
          );
        }

        final topics = tp.filteredTopics;
        final footer = tp.hiddenCount > 0 || !tp.hideSystem
            ? TextButton(
                onPressed: () => tp.setHideSystem(!tp.hideSystem),
                child: Text(tp.hideSystem
                    ? 'Show ${tp.hiddenCount} system topic${tp.hiddenCount == 1 ? '' : 's'} (/rosout, …)'
                    : 'Hide system topics'),
              )
            : null;

        if (topics.isEmpty) {
          final filtering = tp.searchQuery.isNotEmpty || tp.typeFilters.isNotEmpty;
          return _Message(
            icon: filtering ? Icons.search_off : Icons.inbox_outlined,
            color: cs.outline,
            text: filtering
                ? 'No topics match the search or filter'
                : 'No topics yet.\nStart your ROS2 nodes, then tap refresh.',
            action: filtering
                ? TextButton(
                    onPressed: tp.clearFilters,
                    child: const Text('Clear filters'),
                  )
                : footer,
          );
        }

        return RefreshIndicator(
          onRefresh: tp.loadTopics,
          child: ListView.builder(
            itemCount: topics.length + 1,
            itemBuilder: (context, i) {
              if (i == topics.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: footer ?? const SizedBox.shrink()),
                );
              }
              final topic = topics[i];
              final highlighted = topic.name == tp.highlightedTopic;
              return ListTile(
                leading: Icon(
                  topicIcon(topic.type),
                  color: hasVisualizer(topic.type) ? cs.primary : cs.outline,
                ),
                title: Text(topic.name,
                    style: TextStyle(fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500)),
                subtitle: Text(topic.type, overflow: TextOverflow.ellipsis),
                selected: highlighted,
                onTap: () => openEcho(context, topic),
                onLongPress: () => showTopicActions(context, topic),
                trailing: IconButton(
                  tooltip: 'More actions for ${topic.name}',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => showTopicActions(context, topic),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.color, required this.text, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 12), action!],
            ],
          ),
        ),
      );
}
