# Robotics Tool

A ROS2 mobile monitoring and visualization app for Android. Connect to a running `rosbridge_server` over WebSocket and monitor your robot in real time.

---

## Features

- **Topic Monitor** — Browse all active ROS2 topics with type filtering and live search
- **Sensor Visualization** — Auto-visualizes LaserScan, Odometry, Twist, Image (raw & compressed), and more
- **Topic Echo** — Subscribe to any topic and stream incoming messages
- **Publish** — Publish messages to any topic with a JSON editor and optional repeat mode
- **Node Graph** — Visualize node-topic connections (force-directed layout)
- **3D Model Viewer** — Load and inspect STL or URDF robot model files
- **Dark / Light Mode** — Follows system theme or set manually in Settings

---

## Requirements

- Android 5.0 (API 21) or higher
- ROS2 environment with `rosbridge_server` running
- Same Wi-Fi network as the Android device

---

## Setup (ROS2 side)

Install rosbridge:
```bash
sudo apt install ros-humble-rosbridge-suite
```

Launch the WebSocket server:
```bash
ros2 launch rosbridge_server rosbridge_websocket_launch.xml
```

Default port: **9090**

---

## Usage

1. Launch the app and tap **Topic Monitor**
2. Enter your PC's IP address and port (default 9090)
3. Tap **Connect**

---

## Build from Source

```bash
git clone https://github.com/PolyGon-13/Robotics-Tool.git
cd Robotics-Tool
flutter pub get
flutter run
```

Release APK:
```bash
flutter build apk --release
```

Release AAB (for Play Store):
```bash
flutter build appbundle --release
```

---

## Developer

**PolyGon**
