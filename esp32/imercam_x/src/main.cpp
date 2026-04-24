#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <NimBLEDevice.h>
#include "esp_camera.h"
#include "soc/rtc_cntl_reg.h"

namespace {

constexpr char kWifiSsid[] = "不许偷网2.0";
constexpr char kWifiPassword[] = "hjq311099";
constexpr char kDeviceName[] = "PetCam";
constexpr char kFallbackApSsid[] = "PetCam-Setup";
constexpr char kFallbackApPassword[] = "12345678";
constexpr char kMdnsHostname[] = "petcam";

constexpr int kLedPin = 2;
constexpr int kBatteryHoldPin = 33;

constexpr int PWDN_GPIO_NUM = -1;
constexpr int RESET_GPIO_NUM = 15;
constexpr int XCLK_GPIO_NUM = 27;
constexpr int SIOD_GPIO_NUM = 25;
constexpr int SIOC_GPIO_NUM = 23;

constexpr int Y2_GPIO_NUM = 32;
constexpr int Y3_GPIO_NUM = 35;
constexpr int Y4_GPIO_NUM = 34;
constexpr int Y5_GPIO_NUM = 5;
constexpr int Y6_GPIO_NUM = 39;
constexpr int Y7_GPIO_NUM = 18;
constexpr int Y8_GPIO_NUM = 36;
constexpr int Y9_GPIO_NUM = 19;
constexpr int VSYNC_GPIO_NUM = 22;
constexpr int HREF_GPIO_NUM = 26;
constexpr int PCLK_GPIO_NUM = 21;

WebServer server(80);

constexpr char kIndexHtml[] PROGMEM = R"HTML(
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>PetCam Live View</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0d1411;
      --panel: rgba(16, 29, 23, 0.9);
      --text: #edf7f0;
      --muted: #9ab4a4;
      --accent: #66d9a3;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      background:
        radial-gradient(circle at top, #1d4330 0%, rgba(13, 20, 17, 0.96) 58%),
        linear-gradient(135deg, #08110d, #17241d);
      color: var(--text);
      font-family: ui-sans-serif, system-ui, sans-serif;
    }
    main {
      width: min(92vw, 960px);
      padding: 22px;
      border-radius: 20px;
      border: 1px solid rgba(255,255,255,0.08);
      background: var(--panel);
      box-shadow: 0 18px 48px rgba(0, 0, 0, 0.3);
    }
    h1 { margin: 0 0 8px; font-size: 1.5rem; }
    p { margin: 0 0 16px; color: var(--muted); }
    img {
      display: block;
      width: 100%;
      aspect-ratio: 4 / 3;
      object-fit: cover;
      border-radius: 14px;
      background: #000;
    }
    .actions {
      margin-top: 14px;
      display: flex;
      gap: 12px;
      flex-wrap: wrap;
    }
    a {
      color: var(--accent);
      text-decoration: none;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <main>
    <h1>M5Stack PetCam</h1>
    <p>Open a single JPEG snapshot or watch the MJPEG stream directly in the browser.</p>
    <img src="/stream" alt="Live camera stream">
    <div class="actions">
      <a href="/capture" target="_blank" rel="noreferrer">Open single snapshot</a>
      <a href="/health" target="_blank" rel="noreferrer">Health check</a>
    </div>
  </main>
</body>
</html>
)HTML";

bool initCamera() {
  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAMESIZE_QVGA;
  config.jpeg_quality = 12;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;

  if (psramFound()) {
    config.fb_count = 2;
    config.fb_location = CAMERA_FB_IN_PSRAM;
  } else {
    config.fb_count = 1;
    config.fb_location = CAMERA_FB_IN_DRAM;
  }

  const esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed: 0x%x\n", err);
    return false;
  }

  sensor_t* sensor = esp_camera_sensor_get();
  if (sensor != nullptr) {
    sensor->set_vflip(sensor, 1);
    sensor->set_brightness(sensor, 1);
    sensor->set_saturation(sensor, -1);
    sensor->set_framesize(sensor, FRAMESIZE_QVGA);
  }

  Serial.println("Camera init OK");
  return true;
}

camera_fb_t* captureFrame() {
  camera_fb_t* fb = esp_camera_fb_get();
  return fb;
}

void handleHealth() {
  IPAddress ip = WiFi.getMode() == WIFI_AP ? WiFi.softAPIP() : WiFi.localIP();

  String body;
  body.reserve(160);
  body += "{\"status\":\"ok\",\"hostname\":\"";
  body += kMdnsHostname;
  body += ".local\",\"ip\":\"";
  body += ip.toString();
  body += "\"}";
  server.send(200, "application/json", body);
}

void handleIndex() {
  server.send_P(200, "text/html; charset=utf-8", kIndexHtml);
}

void handleCapture() {
  Serial.println("Capture requested");
  camera_fb_t* fb = captureFrame();
  if (fb == nullptr) {
    Serial.println("Capture failed: frame buffer is null");
    server.send(500, "application/json", "{\"error\":\"capture_failed\"}");
    return;
  }

  Serial.printf("Capture OK: %u bytes\n", fb->len);
  WiFiClient client = server.client();
  client.printf(
      "HTTP/1.1 200 OK\r\n"
      "Content-Type: image/jpeg\r\n"
      "Content-Length: %u\r\n"
      "Connection: close\r\n\r\n",
      fb->len);
  client.write(fb->buf, fb->len);
  esp_camera_fb_return(fb);
}

void handleCaptureMeta() {
  String imageUrl = "/captures/latest.jpg?ts=";
  imageUrl += String(millis());

  String body;
  body.reserve(128);
  body += "{\"status\":\"ok\",\"filename\":\"latest.jpg\",\"image_url\":\"";
  body += imageUrl;
  body += "\"}";
  server.send(200, "application/json", body);
}

void handleStream() {
  Serial.println("Stream requested");

  WiFiClient client = server.client();
  client.printf(
      "HTTP/1.1 200 OK\r\n"
      "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n"
      "Cache-Control: no-cache\r\n"
      "Pragma: no-cache\r\n"
      "Connection: close\r\n\r\n");

  while (client.connected()) {
    camera_fb_t* fb = captureFrame();
    if (fb == nullptr) {
      Serial.println("Stream frame failed: frame buffer is null");
      delay(100);
      continue;
    }

    client.printf(
        "--frame\r\n"
        "Content-Type: image/jpeg\r\n"
        "Content-Length: %u\r\n\r\n",
        fb->len);
    client.write(fb->buf, fb->len);
    client.print("\r\n");
    esp_camera_fb_return(fb);

    if (!client.connected()) {
      break;
    }
    delay(60);
  }

  Serial.println("Stream ended");
}

void handleNotFound() {
  String message;
  message.reserve(128);
  message += "PetCam is running.\n";
  message += "GET /\n";
  message += "GET /health\n";
  message += "GET /capture\n";
  message += "GET /capture-meta\n";
  message += "GET /captures/latest.jpg\n";
  message += "GET /stream\n";
  server.send(200, "text/plain", message);
}

void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(true);
  Serial.println("Scanning nearby Wi-Fi networks...");
  const int networkCount = WiFi.scanNetworks(false, true);
  if (networkCount <= 0) {
    Serial.println("No Wi-Fi networks found");
  } else {
    for (int i = 0; i < networkCount; ++i) {
      Serial.printf(
          "[%d] SSID=%s RSSI=%d ENC=%d CH=%d\n",
          i,
          WiFi.SSID(i).c_str(),
          WiFi.RSSI(i),
          static_cast<int>(WiFi.encryptionType(i)),
          WiFi.channel(i));
    }
  }
  WiFi.scanDelete();

  WiFi.begin(kWifiSsid, kWifiPassword);

  Serial.print("Connecting to Wi-Fi");
  const unsigned long startMs = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startMs < 15000) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("Connected. IP: ");
    Serial.println(WiFi.localIP());
    if (MDNS.begin(kMdnsHostname)) {
      MDNS.addService("http", "tcp", 80);
      Serial.printf("mDNS ready: http://%s.local\n", kMdnsHostname);
    } else {
      Serial.println("mDNS start failed");
    }
    return;
  }

  Serial.printf("Wi-Fi connect failed, status=%d\n", static_cast<int>(WiFi.status()));
  WiFi.disconnect(true, true);
  delay(200);

  Serial.printf("Starting fallback AP: %s\n", kFallbackApSsid);
  WiFi.mode(WIFI_AP);
  WiFi.softAP(kFallbackApSsid, kFallbackApPassword);
  Serial.print("AP IP: ");
  Serial.println(WiFi.softAPIP());
}

void startServer() {
  server.on("/", HTTP_GET, handleIndex);
  server.on("/health", HTTP_GET, handleHealth);
  server.on("/capture", HTTP_GET, handleCapture);
  server.on("/capture-meta", HTTP_GET, handleCaptureMeta);
  server.on("/captures/latest.jpg", HTTP_GET, handleCapture);
  server.on("/stream", HTTP_GET, handleStream);
  server.onNotFound(handleNotFound);
  server.begin();
  Serial.println("HTTP server started");
}

void startBleAdvertising() {
  NimBLEDevice::init(kDeviceName);
  NimBLEDevice::setPower(ESP_PWR_LVL_P7);

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  NimBLEAdvertisementData advertisementData;
  advertisementData.setName(kDeviceName);
  advertising->setAdvertisementData(advertisementData);
  advertising->start();
  Serial.printf("BLE advertising as %s\n", kDeviceName);
}

}  // namespace

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

  pinMode(kBatteryHoldPin, OUTPUT);
  digitalWrite(kBatteryHoldPin, HIGH);
  delay(20);

  pinMode(kLedPin, OUTPUT);
  digitalWrite(kLedPin, HIGH);

  Serial.begin(115200);
  delay(1500);

  Serial.println();
  Serial.println("imercam_x boot");
  Serial.printf("PSRAM: %s\n", psramFound() ? "yes" : "no");

  if (!initCamera()) {
    Serial.println("Restarting in 5 seconds...");
    delay(5000);
    ESP.restart();
  }

  startBleAdvertising();
  connectWifi();
  startServer();
}

void loop() {
  server.handleClient();
}
