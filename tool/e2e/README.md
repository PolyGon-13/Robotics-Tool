# E2E checks without a robot

Drive the app in a browser against a fake rosbridge server, so screens and
visualizations can be checked without ROS2 or an Android device. The app
ships for Android only; the web build here is a throwaway test harness.

## Requirements

- Flutter SDK
- Python 3 with `websockets` (`pip install websockets`)
- Node.js with Playwright and Chromium (`npm i -g playwright && npx playwright install chromium`)

## Run

```bash
# 1. Fake robot: 16 topics (LaserScan, Odometry, Imu, JointState, images, ...)
python3 tool/e2e/mock_rosbridge.py 9090 &

# 2. Web build of the app (copied to /tmp/robotics_tool_web, repo untouched)
tool/e2e/build_web.sh            # add --debug to keep Flutter assertions on
python3 -m http.server 8080 --directory /tmp/robotics_tool_web/build/web &

# 3. Screenshot every screen and visualization (light, then dark)
NODE_PATH=$(npm root -g) node tool/e2e/audit.js e2e-shots
NODE_PATH=$(npm root -g) node tool/e2e/audit.js e2e-shots dark

# 4. Reconnect / stale-data scenarios
NODE_PATH=$(npm root -g) node tool/e2e/scenarios.js
```

`audit.js` prints the labels found on each screen and any Flutter exception
the page logged; a clean run ends with `errors: none`.

Mock server controls:

| Signal | Effect |
|---|---|
| `kill -USR1 <pid>` | Drop every client connection (network blip) |
| `kill -USR2 <pid>` | Pause / resume all topic streams (publisher stalls) |

`contact_sheet.js out.png 4 a.png b.png ...` tiles screenshots into one image
for review.
