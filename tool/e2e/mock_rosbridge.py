"""Fake rosbridge_server for exercising the app without a ROS2 install.

Only depends on `websockets` (pip install websockets).

- Answers /rosapi/{topics,nodes,publishers,subscribers}
- Streams fake messages for a small "robot" (lidar, odom, camera, IMU,
  joints, battery, ...) to every client that subscribes
- Logs every op it receives as one JSON line on stdout
- SIGUSR1 drops every client connection (simulates a network blip)
- SIGUSR2 pauses/resumes all streams (simulates a publisher that stalls)

Usage: python3 mock_rosbridge.py [port]
"""
import asyncio
import base64
import json
import math
import signal
import struct
import sys
import time
import zlib

import websockets

RATE_HZ = {
    "/scan": 10, "/odom": 20, "/cmd_vel": 10, "/battery_state": 1,
    "/imu/data": 50, "/joint_states": 20, "/camera/image_raw": 5,
    "/camera/image_raw/compressed": 5, "/camera/depth/image_raw": 5, "/ultrasonic/front": 10,
    "/goal_pose": 1, "/robot_status": 1, "/emergency_stop": 2,
    "/battery_voltage": 2, "/rosout": 2, "/parameter_events": 0,
    "/tf": 30,
}
TOPICS = {
    "/scan": "sensor_msgs/msg/LaserScan",
    "/odom": "nav_msgs/msg/Odometry",
    "/cmd_vel": "geometry_msgs/msg/Twist",
    "/battery_state": "sensor_msgs/msg/BatteryState",
    "/battery_voltage": "std_msgs/msg/Float32",
    "/imu/data": "sensor_msgs/msg/Imu",
    "/joint_states": "sensor_msgs/msg/JointState",
    "/camera/image_raw": "sensor_msgs/msg/Image",
    "/camera/image_raw/compressed": "sensor_msgs/msg/CompressedImage",
    "/camera/depth/image_raw": "sensor_msgs/msg/Image",
    "/ultrasonic/front": "sensor_msgs/msg/Range",
    "/goal_pose": "geometry_msgs/msg/PoseStamped",
    "/robot_status": "std_msgs/msg/String",
    "/emergency_stop": "std_msgs/msg/Bool",
    "/tf": "tf2_msgs/msg/TFMessage",
    "/rosout": "rcl_interfaces/msg/Log",
    "/parameter_events": "rcl_interfaces/msg/ParameterEvent",
}
PUBS = {
    "/scan": ["/lidar_driver"], "/odom": ["/diff_drive_controller"],
    "/cmd_vel": ["/teleop_twist", "/nav2_controller"],
    "/battery_state": ["/battery_monitor"], "/battery_voltage": ["/battery_monitor"],
    "/imu/data": ["/imu_driver"], "/joint_states": ["/joint_state_broadcaster"],
    "/camera/image_raw": ["/camera_driver"],
    "/camera/image_raw/compressed": ["/camera_driver"],
    "/camera/depth/image_raw": ["/camera_driver"],
    "/ultrasonic/front": ["/ultrasonic_driver"], "/goal_pose": ["/rviz2"],
    "/robot_status": ["/robot_manager"], "/emergency_stop": ["/robot_manager"],
    "/tf": ["/robot_state_publisher", "/diff_drive_controller"],
    "/rosout": ["/lidar_driver", "/robot_manager"], "/parameter_events": [],
}
SUBS = {
    "/scan": ["/slam_toolbox", "/nav2_controller"], "/odom": ["/slam_toolbox", "/nav2_controller"],
    "/cmd_vel": ["/diff_drive_controller"], "/battery_state": ["/robot_manager"],
    "/battery_voltage": [], "/imu/data": ["/ekf_filter"],
    "/joint_states": ["/robot_state_publisher"], "/camera/image_raw": [],
    "/camera/image_raw/compressed": [], "/camera/depth/image_raw": [], "/ultrasonic/front": ["/robot_manager"],
    "/goal_pose": ["/nav2_controller"], "/robot_status": [], "/emergency_stop": ["/diff_drive_controller"],
    "/tf": ["/slam_toolbox", "/nav2_controller"], "/rosout": [], "/parameter_events": [],
}
NODES = sorted({n for d in (PUBS, SUBS) for v in d.values() for n in v})

clients = set()
paused = False
T0 = time.time()


def log(**kw):
    print(json.dumps({"t": round(time.time() - T0, 2), **kw}), flush=True)


def stamp():
    t = time.time()
    return {"sec": int(t), "nanosec": int((t % 1) * 1e9)}


def header(frame):
    return {"stamp": stamp(), "frame_id": frame}


def quat_z(yaw):
    return {"x": 0.0, "y": 0.0, "z": math.sin(yaw / 2), "w": math.cos(yaw / 2)}


def room_scan(t):
    """Robot in a 6x4 m room with a box obstacle; some beams return inf."""
    n = 360
    amin, amax = -math.pi, math.pi
    inc = (amax - amin) / n
    rx, ry = 0.5 * math.sin(t * 0.2), 0.0
    ranges = []
    for i in range(n):
        a = amin + i * inc
        dx, dy = math.cos(a), math.sin(a)
        best = math.inf
        for wall in (3.0, -3.0):          # x walls
            if abs(dx) > 1e-6:
                d = (wall - rx) / dx
                if d > 0 and abs(ry + d * dy) <= 2.0:
                    best = min(best, d)
        for wall in (2.0, -2.0):          # y walls
            if abs(dy) > 1e-6:
                d = (wall - ry) / dy
                if d > 0 and abs(rx + d * dx) <= 3.0:
                    best = min(best, d)
        # 0.6 m box obstacle at (1.5, 0.8)
        for k in range(1, 400):
            d = k * 0.01
            px, py = rx + d * dx, ry + d * dy
            if abs(px - 1.5) < 0.3 and abs(py - 0.8) < 0.3:
                best = min(best, d)
                break
            if d > best:
                break
        if 100 <= i < 115:                # doorway: no return
            best = math.inf
        ranges.append(round(best + 0.01 * math.sin(i * 7 + t * 13), 3) if math.isfinite(best) else None)
    return {"header": header("laser"), "angle_min": amin, "angle_max": amax,
            "angle_increment": inc, "time_increment": 0.0, "scan_time": 0.1,
            "range_min": 0.12, "range_max": 8.0, "ranges": ranges, "intensities": []}


def png_bytes(w, h, rgb_rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rgb_rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def test_pattern(w, h, t):
    rows = []
    cx = (math.sin(t) * 0.3 + 0.5) * w
    for y in range(h):
        row = []
        for x in range(w):
            inside = (x - cx) ** 2 + (y - h / 2) ** 2 < (h / 5) ** 2
            row += [255, 80, 40] if inside else [int(255 * x / w), int(255 * y / h), 160]
        rows.append(row)
    return rows


def fake_msg(topic, k):
    t = k / max(RATE_HZ.get(topic, 10), 1)
    if topic == "/scan":
        return room_scan(t)
    if topic == "/odom":
        yaw = t * 0.3
        return {"header": header("odom"), "child_frame_id": "base_link",
                "pose": {"pose": {"position": {"x": 1.5 * math.sin(t * 0.3), "y": 1.0 * math.sin(t * 0.6), "z": 0.0},
                                  "orientation": quat_z(yaw)}, "covariance": [0.0] * 36},
                "twist": {"twist": {"linear": {"x": 0.3 + 0.1 * math.sin(t), "y": 0.0, "z": 0.0},
                                    "angular": {"x": 0.0, "y": 0.0, "z": 0.3 * math.cos(t * 0.5)}},
                          "covariance": [0.0] * 36}}
    if topic == "/cmd_vel":
        return {"linear": {"x": round(0.4 * math.sin(t * 0.5), 3), "y": 0.0, "z": 0.0},
                "angular": {"x": 0.0, "y": 0.0, "z": round(0.8 * math.cos(t * 0.3), 3)}}
    if topic == "/battery_state":
        pct = max(0.05, 0.82 - t * 0.001)
        return {"header": header("base_link"), "voltage": round(10.8 + 1.8 * pct, 2), "temperature": 31.5,
                "current": -1.9, "charge": pct * 5.0, "capacity": 5.0, "design_capacity": 5.2,
                "percentage": round(pct, 3), "power_supply_status": 2, "power_supply_health": 1,
                "power_supply_technology": 3, "present": True, "cell_voltage": [], "cell_temperature": [],
                "location": "base", "serial_number": "BAT-001"}
    if topic == "/battery_voltage":
        return {"data": round(12.3 - t * 0.002 + 0.03 * math.sin(t * 3), 3)}
    if topic == "/imu/data":
        return {"header": header("imu_link"),
                "orientation": {"x": 0.02 * math.sin(t), "y": 0.01, "z": math.sin(t * 0.15), "w": math.cos(t * 0.15)},
                "orientation_covariance": [0.0] * 9,
                "angular_velocity": {"x": 0.02 * math.sin(t * 5), "y": 0.01, "z": 0.3 * math.cos(t * 0.5)},
                "angular_velocity_covariance": [0.0] * 9,
                "linear_acceleration": {"x": 0.2 * math.sin(t * 2), "y": 0.05, "z": 9.81 + 0.05 * math.sin(t * 9)},
                "linear_acceleration_covariance": [0.0] * 9}
    if topic == "/joint_states":
        names = ["left_wheel_joint", "right_wheel_joint", "shoulder_pitch", "shoulder_roll", "elbow", "wrist"]
        return {"header": header(""), "name": names,
                "position": [round(t * 3 % (2 * math.pi) - math.pi, 3), round(t * 2.8 % (2 * math.pi) - math.pi, 3),
                             round(0.8 * math.sin(t), 3), round(0.3 * math.sin(t * 0.7), 3),
                             round(1.2 + 0.5 * math.sin(t * 1.3), 3), round(0.4 * math.cos(t), 3)],
                "velocity": [3.0, 2.8, round(0.8 * math.cos(t), 3), 0.2, 0.6, -0.4],
                "effort": [0.5, 0.48, 2.1, 0.8, 1.4, 0.2]}
    if topic == "/camera/image_raw":
        w, h = 80, 60
        data = bytes(v for row in test_pattern(w, h, t) for v in row)
        return {"header": header("camera"), "height": h, "width": w, "encoding": "rgb8",
                "is_bigendian": 0, "step": w * 3, "data": base64.b64encode(data).decode()}
    if topic == "/camera/image_raw/compressed":
        w, h = 160, 120
        return {"header": header("camera"), "format": "png",
                "data": base64.b64encode(png_bytes(w, h, test_pattern(w, h, t))).decode()}
    if topic == "/camera/depth/image_raw":
        # 16UC1 depth in mm: a tilted floor with a box in front, 0 = no reading
        w, h = 80, 60
        buf = bytearray()
        for y in range(h):
            for x in range(w):
                d = 0 if y < 4 else int(4000 - 45 * y + 200 * math.sin(t))
                if abs(x - 40 - 15 * math.sin(t)) < 10 and 20 < y < 45:
                    d = 900
                buf += struct.pack("<H", max(0, d))
        return {"header": header("camera_depth"), "height": h, "width": w, "encoding": "16UC1",
                "is_bigendian": 0, "step": w * 2, "data": base64.b64encode(bytes(buf)).decode()}
    if topic == "/ultrasonic/front":
        return {"header": header("us_front"), "radiation_type": 0, "field_of_view": 0.5,
                "min_range": 0.02, "max_range": 4.0, "range": round(1.2 + 0.8 * math.sin(t * 0.8), 3)}
    if topic == "/goal_pose":
        return {"header": header("map"), "pose": {"position": {"x": 2.0, "y": -1.0, "z": 0.0},
                                                  "orientation": quat_z(math.pi / 2)}}
    if topic == "/robot_status":
        return {"data": ["IDLE", "NAVIGATING", "DOCKING"][int(t / 5) % 3]}
    if topic == "/emergency_stop":
        return {"data": int(t / 10) % 4 == 3}
    if topic == "/tf":
        def tf(parent, child, x, y, z, yaw):
            return {"header": header(parent), "child_frame_id": child,
                    "transform": {"translation": {"x": x, "y": y, "z": z}, "rotation": quat_z(yaw)}}
        return {"transforms": [
            tf("map", "odom", 0.12, -0.05, 0.0, 0.02),
            tf("odom", "base_link", 1.5 * math.sin(t * 0.3), 1.0 * math.sin(t * 0.6), 0.0, t * 0.3),
            tf("base_link", "laser", 0.1, 0.0, 0.25, 0.0),
            tf("base_link", "imu_link", 0.0, 0.0, 0.05, 0.0),
            tf("base_link", "camera", 0.15, 0.0, 0.3, 0.0),
        ]}
    if topic == "/rosout":
        return {"stamp": stamp(), "level": 20, "name": "robot_manager",
                "msg": f"heartbeat {k}", "file": "manager.cpp", "function": "tick", "line": 42}
    return {}


async def stream(ws, topic):
    hz = RATE_HZ.get(topic, 10)
    if hz <= 0:
        return
    k = 0
    while True:
        if not paused:
            await ws.send(json.dumps({"op": "publish", "topic": topic, "msg": fake_msg(topic, k)},
                                     allow_nan=False))
            k += 1
        await asyncio.sleep(1 / hz)


async def handler(ws):
    cid = id(ws) % 10000
    clients.add(ws)
    log(ev="client_connected", cid=cid)
    streams = {}
    try:
        async for raw in ws:
            m = json.loads(raw)
            op = m.get("op")
            log(ev="op", cid=cid, op=op, **{k: m[k] for k in ("service", "topic", "type") if k in m})
            if op == "call_service":
                svc, args = m["service"], m.get("args") or {}
                if svc == "/rosapi/topics":
                    vals = {"topics": list(TOPICS), "types": list(TOPICS.values())}
                elif svc == "/rosapi/nodes":
                    vals = {"nodes": NODES}
                elif svc == "/rosapi/publishers":
                    vals = {"publishers": PUBS.get(args.get("topic"), [])}
                elif svc == "/rosapi/subscribers":
                    vals = {"subscribers": SUBS.get(args.get("topic"), [])}
                else:
                    vals = {}
                await ws.send(json.dumps({"op": "service_response", "id": m["id"],
                                          "service": svc, "values": vals, "result": True}))
            elif op == "subscribe" and m["topic"] not in streams:
                streams[m["topic"]] = asyncio.create_task(stream(ws, m["topic"]))
            elif op == "unsubscribe" and m["topic"] in streams:
                streams.pop(m["topic"]).cancel()
    except websockets.ConnectionClosed:
        pass
    finally:
        for s in streams.values():
            s.cancel()
        clients.discard(ws)
        log(ev="client_disconnected", cid=cid)


async def main(port):
    loop = asyncio.get_running_loop()

    def drop_all():
        log(ev="dropping_all_clients", n=len(clients))
        for ws in list(clients):
            ws.transport.abort()

    def toggle_pause():
        global paused
        paused = not paused
        log(ev="streams_paused" if paused else "streams_resumed")

    loop.add_signal_handler(signal.SIGUSR1, drop_all)
    loop.add_signal_handler(signal.SIGUSR2, toggle_pause)
    async with websockets.serve(handler, "0.0.0.0", port, max_size=None):
        log(ev="listening", port=port)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main(int(sys.argv[1]) if len(sys.argv) > 1 else 9090))
