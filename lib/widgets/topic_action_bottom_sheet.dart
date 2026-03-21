import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ros_topic.dart';
import '../providers/topic_provider.dart';
import '../screens/publish_screen.dart';
import '../screens/visualization_screen.dart';

class TopicActionBottomSheet extends StatelessWidget {
  final RosTopic topic;

  const TopicActionBottomSheet({super.key, required this.topic});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 헤더: 토픽 이름 + 타입
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(topic.name,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(topic.type,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Divider(),

          // 📊 Topic Echo
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Topic Echo'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VisualizationScreen(
                    topic: topic.name,
                    type: topic.type,
                  ),
                ),
              );
            },
          ),

          // 📤 Publish
          ListTile(
            leading: const Icon(Icons.upload),
            title: const Text('Publish'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PublishScreen(
                    topic: topic.name,
                    type: topic.type,
                  ),
                ),
              );
            },
          ),

          // 🔗 Graph 하이라이트
          ListTile(
            leading: const Icon(Icons.account_tree),
            title: const Text('Highlight in Graph'),
            onTap: () {
              context.read<TopicProvider>().setHighlight(topic.name);
              Navigator.pop(context);
            },
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
