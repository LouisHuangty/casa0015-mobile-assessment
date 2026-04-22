# Pet Beacon

Pet Beacon is a Flutter mobile app for pet tracking experiments. This version extends the earlier mock-data build with Bluetooth Low Energy scanning so the app can detect nearby BLE devices and use signal strength as part of the tracking experience.

## Current Version

This version includes:

- Firebase email/password login and registration
- Firestore-based user profile storage
- Pet profile setup with pet name and pet type
- Multi-page app navigation
- BLE device scanning
- Selection of a nearby BLE device
- RSSI-based proximity feedback for tracking states
- TimerCAM camera service integration
- Manual camera health checks and test capture
- BLE lost automatic capture trigger
- Prototype history, tracking, and device status screens

## Main Idea

The app is designed to help a pet owner monitor a pet tag and quickly check relevant information in one place. The current build combines account setup, profile information, BLE scanning, and a camera service to support a simple pet-tracking workflow.

Some parts of the experience still use placeholder data, but the Bluetooth scanning flow and camera-trigger flow are now integrated into the app structure.

## Bluetooth Feature

The BLE part of the app is used to:

- scan for nearby Bluetooth Low Energy devices
- display detected devices and identifiers
- show whether devices are connectable
- monitor RSSI signal strength
- map signal strength to simple pet proximity states

This version is intended for testing BLE discovery, camera triggering, and cross-device interaction rather than as a final production-ready tracking system.

## Tech Stack

- Flutter
- Dart
- Firebase Authentication
- Cloud Firestore
- FlutterBluePlus

## Project Structure

- `lib/main.dart`: main application UI, BLE flow, and tracking logic
- `lib/firebase_options.dart`: Firebase platform configuration
- `ios/Runner/Info.plist`: iOS Bluetooth permission text
- `android/` and `ios/`: mobile platform configuration
- `esp32/petracker/`: earlier ESP32-CAM firmware experiment
- `esp32/imercam_x/`: active M5Stack TimerCAM firmware project
- `raspberry_pi/petcam/`: earlier Raspberry Pi camera service experiment

## Running the App

1. Install Flutter and platform dependencies.
2. Run `flutter pub get`.
3. Ensure Firebase configuration files are present for the target platform.
4. Enable Bluetooth permissions on the device.
5. Run the app with `flutter run`.

## TimerCAM Camera Flow

The current integrated camera path uses the M5Stack TimerCAM firmware in `esp32/imercam_x/`.

1. Open `esp32/imercam_x/` in PlatformIO or VS Code.
2. Build and upload the firmware to the TimerCAM board.
3. Power the board and let it join the same Wi-Fi network as the phone.
4. Confirm these endpoints work from the phone or laptop:
   `http://<camera-ip>/health`
   `http://<camera-ip>/capture-meta`
   `http://<camera-ip>/stream`
5. In the Flutter app, open the `Device` tab and use `Detect Camera Service`.
6. Use `Test Camera Capture` before validating automatic BLE lost capture.

The TimerCAM firmware now supports:

- battery hold via `IO33`
- camera health responses
- single image capture
- MJPEG stream preview
- BLE lost compatible `capture-meta` responses for the app

## Notes

- This repository is part of the CASA0015 Mobile Systems & Interactions coursework development process.
- The app currently combines live BLE scanning, camera health checks, manual capture, and BLE lost automatic capture.
- Future versions can extend the BLE workflow with stronger device pairing, more robust connection handling, and fuller real-world tracking logic.
