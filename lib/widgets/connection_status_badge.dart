import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';

class ConnectionStatusBadge extends StatelessWidget {
  const ConnectionStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, conn, _) {
        final cs = Theme.of(context).colorScheme;

        final (color, label) = switch (conn.status) {
          ConnectionStatus.connecting  => (cs.tertiary, 'Connecting…'),
          ConnectionStatus.connected   => (cs.primary,  'Connected'),
          ConnectionStatus.failed      => (cs.error,    'Connection Failed'),
          ConnectionStatus.disconnected => (cs.outline, 'Disconnected'),
        };

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color)),
          ],
        );
      },
    );
  }
}
