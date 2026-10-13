import cv2
import time
import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

SETTINGS_FILE = "/tmp/camera_settings.json"

def load_settings():
    if os.path.exists(SETTINGS_FILE):
        with open(SETTINGS_FILE, 'r') as f:
            return json.load(f)
    return None

latest_frame = None
cap = None

def connect_camera():
    global cap
    settings = load_settings()
    if not settings:
        print("No camera settings found")
        return False
    
    rtsp_url = f"rtsp://{settings['username']}:{settings['password']}@{settings['ip']}/Streaming/Channels/101"
    print(f"Connecting to: {rtsp_url}")
    
    if cap:
        cap.release()
    
    cap = cv2.VideoCapture(rtsp_url, cv2.CAP_FFMPEG)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 2560)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 1440)
    
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"Resolution: {width}x{height}")
    
    if not cap.isOpened():
        print("ERROR: Cannot open RTSP stream")
        return False
    
    print("RTSP stream opened")
    return True

class FrameHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global latest_frame
        if self.path == '/frame':
            self.send_response(200)
            self.send_header('Content-type', 'image/jpeg')
            self.end_headers()
            if latest_frame is not None:
                self.wfile.write(latest_frame)
        else:
            self.send_response(404)
    
    def log_message(self, format, *args):
        pass

# Start HTTP server
server = HTTPServer(('localhost', 8888), FrameHandler)
import threading
threading.Thread(target=server.serve_forever, daemon=True).start()
print("HTTP server started on port 8888")

# Load saved camera
if load_settings():
    connect_camera()
else:
    print("Waiting for camera settings...")

while True:
    if cap and cap.isOpened():
        ret, frame = cap.read()
        if ret:
            _, encoded = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
            latest_frame = encoded.tobytes()
    time.sleep(0.01)