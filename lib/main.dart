import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/connection_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/topic_provider.dart';
import 'screens/connection_screen.dart';
import 'screens/home_screen.dart';
import 'screens/main_screen.dart';
import 'screens/model_viewer_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final themeProvider = await ThemeProvider().load();
  runApp(RosMobileApp(themeProvider: themeProvider));
}

class RosMobileApp extends StatelessWidget {
  final ThemeProvider themeProvider;

  const RosMobileApp({super.key, required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProxyProvider<ConnectionProvider, TopicProvider>(
          create: (_) => TopicProvider(),
          update: (_, conn, topic) {
            topic!.updateService(conn.service, conn.status);
            return topic;
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (_, tp, _) => MaterialApp(
          title: 'Robotics-Tool',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: tp.themeMode,
          initialRoute: '/',
          routes: {
            '/':           (_) => const HomeScreen(),
            '/connection': (_) => const ConnectionScreen(),
            '/main':       (_) => const MainScreen(),
            '/model':      (_) => const ModelViewerScreen(),
          },
        ),
      ),
    );
  }
}
