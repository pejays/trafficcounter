import cv2
import time
import json
import threading
import os
import math
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, quote
from inference import get_model

# Ask FFmpeg for the newest RTSP packets instead of building up a playback
# buffer. This is applied before each VideoCapture is opened.
os.environ.setdefault("OPENCV_FFMPEG_CAPTURE_OPTIONS", "rtsp_transport;tcp|fflags;nobuffer|flags;low_delay|max_delay;0")

# ── Camera configuration ────────────────────────────────────────
# Swift writes the selected camera to this local file before starting this
# helper. Keeping the address out of source lets the same desktop app work on
# any network that can route to the selected camera.
CAMERA_SETTINGS_PATH = "/tmp/camera_settings.json"
camera_settings_lock = threading.Lock()
camera_settings_revision = 0
rtsp_url = None


def build_rtsp_url(ip, username, password):
    host = (ip or "").strip()
    if not host:
        return None
    if host.startswith("rtsp://") or host.startswith("rtsps://"):
        return host
    return "rtsp://{}:{}@{}/Streaming/Channels/101".format(
        quote(username or "", safe=""), quote(password or "", safe=""), host
    )


def set_camera_settings(ip, username, password, persist=False):
    global rtsp_url, camera_settings_revision
    new_url = build_rtsp_url(ip, username, password)
    if new_url is None:
        return False
    with camera_settings_lock:
        rtsp_url = new_url
        camera_settings_revision += 1
    if persist:
        with open(CAMERA_SETTINGS_PATH, "w") as settings_file:
            json.dump({"ip": ip, "username": username, "password": password}, settings_file)
    return True


def load_camera_settings():
    try:
        with open(CAMERA_SETTINGS_PATH, "r") as settings_file:
            settings = json.load(settings_file)
        return set_camera_settings(
            settings.get("ip", ""), settings.get("username", ""), settings.get("password", "")
        )
    except (OSError, ValueError, TypeError):
        return False

# Keep one traffic-class model loaded. The previous generic fallback doubled
# the model footprint but returned generic COCO labels that do not map to this
# app's eight traffic classes, so it did not improve the stored counts.
my_model = get_model(
    model_id="vehicle-counting-capstone/traffic-vehicle-detection-e6kgi-8-yolov8n-t1",
    api_key="KkQmnnFuctgmAmbTLOW6"
)

PROCESSING_SIZE = (1280, 720)
PREVIEW_SIZE = (1920, 1080)
PREVIEW_JPEG_QUALITY = 88
MAX_TARGET_FPS = 30
MIN_TARGET_FPS = 10
adaptive_target_fps = float(MAX_TARGET_FPS)
processing_time_ema = None
last_fps_adjustment = 0.0

# Global variables shared by the capture, detection, and local HTTP threads.
# Capture keeps the preview independent from the (slower) ML inference loop.
latest_frame = None
latest_frame_lock = threading.Lock()
latest_source_frame = None
latest_source_revision = 0
latest_source_lock = threading.Lock()
latest_detections = []
latest_detections_lock = threading.Lock()
load_camera_settings()


def adapt_target_fps(processing_seconds):
    """Target 30 FPS when capacity is available, then back off gracefully.

    No extra monitoring package is required: the detector's own frame time is
    the most direct signal of available capacity, while the system load guards
    against sustained CPU pressure.
    """
    global adaptive_target_fps, processing_time_ema, last_fps_adjustment
    processing_time_ema = processing_seconds if processing_time_ema is None else (
        processing_time_ema * 0.8 + processing_seconds * 0.2
    )
    now = time.monotonic()
    if now - last_fps_adjustment < 1:
        return adaptive_target_fps
    last_fps_adjustment = now

    sustainable_fps = 1 / max(processing_time_ema * 1.15, 1 / MAX_TARGET_FPS)
    target = min(MAX_TARGET_FPS, max(MIN_TARGET_FPS, sustainable_fps))
    try:
        normalized_load = os.getloadavg()[0] / max(os.cpu_count() or 1, 1)
        if normalized_load > 0.85:
            target = max(MIN_TARGET_FPS, min(target, adaptive_target_fps - 2))
    except OSError:
        pass

    # Move upward slowly to avoid oscillation, but lower immediately when a
    # frame cannot keep up with the current target.
    if target < adaptive_target_fps:
        adaptive_target_fps = target
    else:
        adaptive_target_fps = min(target, adaptive_target_fps + 1)
    return adaptive_target_fps


def load_line_pos():
    if os.path.exists("/tmp/line_pos.txt"):
        try:
            with open("/tmp/line_pos.txt", "r") as f:
                return float(f.read())
        except:
            return 0.7
    return 0.7


def save_line_pos(pos):
    with open("/tmp/line_pos.txt", "w") as f:
        f.write(str(pos))
    

def load_line_angle():
    if os.path.exists("/tmp/line_angle.txt"):
        try:
            with open("/tmp/line_angle.txt", "r") as f:
                return float(f.read())
        except:
            return 0.0
    return 0.0


def save_line_angle(angle):
    with open("/tmp/line_angle.txt", "w") as f:
        f.write(str(angle))


# New flag to control counting based on schedule
counting_enabled = False

line_y_position = load_line_pos()
line_angle = load_line_angle()

vehicle_counts = {
    "private car": 0, "jeepney": 0, "uv": 0, "bus-minibus": 0,
    "light truck": 0, "heavy truck": 0, "motorcycle": 0, "tricycle": 0
}
active_vehicles = {}
lost_vehicles = {}
total_unique_ids = set()
next_vehicle_id = 0


# ── Capture and detection threads ───────────────────────────────
def get_center(bbox):
    x1, y1, x2, y2 = bbox
    return ((x1 + x2) // 2, (y1 + y2) // 2)


def rotated_line(frame_width, frame_height):
    line_y = int(frame_height * line_y_position)
    slope = math.tan(math.radians(line_angle))
    intercept = line_y - slope * (frame_width / 2)
    return slope, intercept


def publish_preview(frame):
    """Encode a current camera frame without waiting for ML inference."""
    global latest_frame
    preview = cv2.resize(frame, PREVIEW_SIZE, interpolation=cv2.INTER_AREA)
    preview_height, preview_width = preview.shape[:2]
    slope, intercept = rotated_line(preview_width, preview_height)
    cv2.line(preview, (0, int(intercept)), (preview_width, int(slope * preview_width + intercept)), (0, 0, 255), 3)

    with latest_detections_lock:
        annotations = list(latest_detections)
    scale_x = preview_width / PROCESSING_SIZE[0]
    scale_y = preview_height / PROCESSING_SIZE[1]
    for vehicle_id, class_name, bbox in annotations:
        x1, y1, x2, y2 = bbox
        x1, x2 = int(x1 * scale_x), int(x2 * scale_x)
        y1, y2 = int(y1 * scale_y), int(y2 * scale_y)
        cv2.rectangle(preview, (x1, y1), (x2, y2), (0, 255, 0), 2)
        cv2.putText(preview, f"ID:{vehicle_id} {class_name}", (x1, max(18, y1 - 5)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)

    encoded_ok, encoded = cv2.imencode('.jpg', preview, [cv2.IMWRITE_JPEG_QUALITY, PREVIEW_JPEG_QUALITY])
    if encoded_ok:
        with latest_frame_lock:
            latest_frame = encoded.tobytes()


def capture_video():
    """Keep the operator preview current at the camera's own frame rate."""
    global latest_source_frame, latest_source_revision, latest_frame
    cap = None
    applied_settings_revision = -1
    while True:
        with camera_settings_lock:
            current_url = rtsp_url
            current_revision = camera_settings_revision
        if current_url is None:
            time.sleep(1)
            continue
        if cap is None or current_revision != applied_settings_revision:
            if cap is not None:
                cap.release()
            cap = cv2.VideoCapture(current_url, cv2.CAP_FFMPEG)
            cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            applied_settings_revision = current_revision
        if not cap.isOpened():
            with latest_frame_lock:
                latest_frame = None
            cap.release()
            cap = None
            time.sleep(2)
            continue
        ret, frame = cap.read()
        if not ret:
            cap.release()
            cap = None
            with latest_frame_lock:
                latest_frame = None
            time.sleep(1)
            continue
        with latest_source_lock:
            latest_source_frame = frame
            latest_source_revision += 1
        publish_preview(frame)


def process_video():
    """Run ML on the newest captured frame; intentionally skip stale frames."""
    global vehicle_counts, active_vehicles, lost_vehicles, total_unique_ids, next_vehicle_id, latest_detections
    confidence_threshold = 0.6
    lost_buffer_frames = 30
    max_match_distance = 80
    processed_revision = -1

    def compute_iou(box_a, box_b):
        ax1, ay1, ax2, ay2 = box_a; bx1, by1, bx2, by2 = box_b
        ix1, iy1 = max(ax1, bx1), max(ay1, by1)
        ix2, iy2 = min(ax2, bx2), min(ay2, by2)
        inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
        union = (ax2 - ax1) * (ay2 - ay1) + (bx2 - bx1) * (by2 - by1) - inter
        return inter / union if union > 0 else 0

    def find_best_match(detection, pool):
        best_id, best_score = None, -1
        cx, cy = get_center(detection["bbox"])
        for vehicle_id, data in pool.items():
            if data["class_name"] != detection["class_name"]:
                continue
            px, py = get_center(data["bbox"])
            distance = ((cx - px) ** 2 + (cy - py) ** 2) ** 0.5
            if distance > max_match_distance:
                continue
            score = compute_iou(detection["bbox"], data["bbox"]) * 0.7 + max(0, 1 - distance / max_match_distance) * 0.3
            if score > best_score:
                best_id, best_score = vehicle_id, score
        return best_id

    while True:
        with latest_source_lock:
            if latest_source_frame is None or latest_source_revision == processed_revision:
                frame, revision = None, processed_revision
            else:
                frame, revision = latest_source_frame.copy(), latest_source_revision
        if frame is None:
            time.sleep(0.01)
            continue
        processed_revision = revision
        started_at = time.monotonic()
        frame = cv2.resize(frame, PROCESSING_SIZE, interpolation=cv2.INTER_AREA)
        height, width = frame.shape[:2]
        slope, intercept = rotated_line(width, height)
        results = my_model.infer(frame)
        detections = []
        for prediction in results[0].predictions:
            if prediction.confidence < confidence_threshold:
                continue
            x1 = int(prediction.x - prediction.width / 2); y1 = int(prediction.y - prediction.height / 2)
            x2 = int(prediction.x + prediction.width / 2); y2 = int(prediction.y + prediction.height / 2)
            detections.append({"bbox": (x1, y1, x2, y2), "class_name": prediction.class_name, "center_y": (y1 + y2) // 2})

        matched_ids = set()
        for detection in detections:
            vehicle_id = find_best_match(detection, active_vehicles)
            if vehicle_id is None or vehicle_id in matched_ids:
                vehicle_id = find_best_match(detection, lost_vehicles)
                if vehicle_id is not None:
                    active_vehicles[vehicle_id] = lost_vehicles.pop(vehicle_id)
                else:
                    vehicle_id = next_vehicle_id
                    next_vehicle_id += 1
                    total_unique_ids.add(vehicle_id)
                    active_vehicles[vehicle_id] = {"class_name": detection["class_name"], "bbox": detection["bbox"], "counted": False, "frames_lost": 0}
            data = active_vehicles[vehicle_id]
            previous_center_y = get_center(data["bbox"])[1]
            current_center_x, current_center_y = get_center(detection["bbox"])
            current_line_y = slope * current_center_x + intercept
            previous_line_y = slope * get_center(data["bbox"])[0] + intercept
            if counting_enabled and previous_center_y < previous_line_y and current_center_y >= current_line_y and not data["counted"]:
                data["counted"] = True
                class_name = detection["class_name"].lower()
                if class_name in vehicle_counts:
                    vehicle_counts[class_name] += 1
            data.update({"bbox": detection["bbox"], "frames_lost": 0})
            matched_ids.add(vehicle_id)

        for vehicle_id in [key for key in active_vehicles if key not in matched_ids]:
            data = active_vehicles.pop(vehicle_id)
            data["frames_lost"] = 1
            lost_vehicles[vehicle_id] = data
        for vehicle_id in list(lost_vehicles):
            lost_vehicles[vehicle_id]["frames_lost"] += 1
            if lost_vehicles[vehicle_id]["frames_lost"] > lost_buffer_frames:
                lost_vehicles.pop(vehicle_id)

        with latest_detections_lock:
            latest_detections = [(vehicle_id, data["class_name"], data["bbox"]) for vehicle_id, data in active_vehicles.items()]
        elapsed = time.monotonic() - started_at
        target_fps = adapt_target_fps(elapsed)
        time.sleep(max(0, (1 / target_fps) - elapsed))


# ── HTTP Server for Swift ────────────────────────────────────────
class FrameHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global line_y_position, line_angle, counting_enabled
        global vehicle_counts, active_vehicles, lost_vehicles, total_unique_ids, next_vehicle_id

        if self.path == '/health':
            # The helper can be running while the upstream RTSP stream is not.
            # Report that distinction so the desktop does not show a false
            # "connected" state on an unreachable Wi-Fi network.
            with latest_frame_lock:
                frame_available = latest_frame is not None
            self.send_response(200 if frame_available else 503)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                "stream_ready": frame_available,
                "target_fps": round(adaptive_target_fps, 1)
            }).encode('utf-8'))

        elif urlparse(self.path).path == '/update':
            query = parse_qs(urlparse(self.path).query)
            updated = set_camera_settings(
                query.get('ip', [''])[0],
                query.get('username', [''])[0],
                query.get('password', [''])[0],
                persist=False
            )
            self.send_response(200 if updated else 400)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"updated": updated}).encode('utf-8'))

        elif self.path == '/frame':
            with latest_frame_lock:
                frame_bytes = latest_frame
            self.send_response(200)
            self.send_header('Content-type', 'image/jpeg')
            self.end_headers()
            if frame_bytes is not None:
                self.wfile.write(frame_bytes)

        elif self.path == '/counts':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            response = json.dumps(vehicle_counts).encode('utf-8')
            self.wfile.write(response)

        elif self.path.startswith('/update_line'):
            query = parse_qs(urlparse(self.path).query)
            if 'y' in query:
                line_y_position = float(query['y'][0])
                save_line_pos(line_y_position)
                print(f"Updated line position to {line_y_position}")
            self.send_response(200)
            self.end_headers()

        elif self.path.startswith('/update_angle'):
            query = parse_qs(urlparse(self.path).query)
            if 'a' in query:
                line_angle = float(query['a'][0])
                save_line_angle(line_angle)
                print(f"Updated line angle to {line_angle}")
            self.send_response(200)
            self.end_headers()

        elif self.path.startswith('/toggle_counting'):
            query = parse_qs(urlparse(self.path).query)
            if 'active' in query:
                counting_enabled = query['active'][0] == '1'
                print(f"Counting enabled: {counting_enabled}")
            self.send_response(200)
            self.end_headers()

        elif self.path == '/reset_counts':
            vehicle_counts = {
                "private car": 0, "jeepney": 0, "uv": 0, "bus-minibus": 0,
                "light truck": 0, "heavy truck": 0, "motorcycle": 0, "tricycle": 0
            }
            active_vehicles = {}
            lost_vehicles = {}
            total_unique_ids = set()
            next_vehicle_id = 0
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"reset": True}).encode('utf-8'))

        else:
            self.send_response(404)

    def log_message(self, format, *args):
        pass


if __name__ == '__main__':
    threading.Thread(target=capture_video, daemon=True).start()
    threading.Thread(target=process_video, daemon=True).start()
    server = ThreadingHTTPServer(('127.0.0.1', 8888), FrameHandler)
    server.daemon_threads = True
    print("HTTP server started on port 8888")
    server.serve_forever()
