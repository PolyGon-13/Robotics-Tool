import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/ros_topic.dart';
import '../providers/topic_provider.dart';
import '../screens/publish_screen.dart';
import '../screens/visualization_screen.dart';
import 'topic_icon.dart';
import 'visualizations/visualizer_registry.dart';

void openEcho(BuildContext context, RosTopic topic) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => VisualizationScreen(topic: topic.name, type: topic.type),
    ),
  );
}

void openPublish(BuildContext context, RosTopic topic) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PublishScreen(topic: topic.name, type: topic.type),
    ),
  );
}

void showTopicActions(BuildContext context, RosTopic topic) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => TopicActionBottomSheet(topic: topic),
  );
}

class TopicActionBottomSheet extends StatelessWidget {
  final RosTopic topic;

  const TopicActionBottomSheet({super.key, required this.topic});

  @override
  Widget build(BuildContext context) {
    final visual = hasVisualizer(topic.type);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(topicIcon(topic.type)),
            title: Text(topic.name, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(topic.type),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.insights),
            title: const Text('Topic Echo'),
            subtitle: Text(visual ? 'Live visualization' : 'Live message view'),
            onTap: () {
              Navigator.pop(context);
              openEcho(context, topic);
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload),
            title: const Text('Publish'),
            subtitle: const Text('Send messages to this topic'),
            onTap: () {
              Navigator.pop(context);
              openPublish(context, topic);
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_tree),
            title: const Text('Show in Graph'),
            subtitle: const Text('Highlight the nodes using this topic'),
            onTap: () {
              context.read<TopicProvider>().showInGraph(topic.name);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy topic name'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: topic.name));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied ${topic.name}'), duration: const Duration(seconds: 1)),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
