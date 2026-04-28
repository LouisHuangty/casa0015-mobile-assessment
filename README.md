# Pet Beacon

Pet Beacon is a Flutter-based mobile app for lightweight pet tracking experiments. The project combines Bluetooth Low Energy scanning, RSSI-based proximity feedback, and a local M5Stack TimerCAM camera service to explore how a pet owner might detect when a tag moves farther away and quickly retrieve a recent visual update.

This repository was developed as part of CASA0015 Mobile Systems & Interactions coursework.

## App Link

- GitHub repository: <https://github.com/LouisHuangty/Pet-Beacon>
- Video demo: <https://youtu.be/nXaRUo2nDik>


## Idea Generation and Research

The idea for Pet Beacon began with a short `Crazy 8's` ideation exercise. This method was used to generate multiple app directions quickly, then narrow them through peer feedback. During that validation stage, animal tracking received strong interest from peers, which suggested that it addressed a recognisable and meaningful need.

The supporting class research notes and idea development material are shown below:

![Idea generation and research](Images/idea-generation-research.jpg)



## Paper Prototyping

The hand-drawn storyboard below reflects the early interaction concept before the interface was fully implemented. It focuses on the main user flow: sign in, register a pet profile, select a BLE tag, monitor proximity, configure the camera service, and review capture history.

![Pet Beacon hand-drawn storyboard](Images/storyboard.png)

## Showcase App

The following screenshots show the implemented app screens that correspond to the early storyboard flow.

<p align="center">
  <img src="Images/showcase1.png" alt="Pet Beacon showcase screen 1" width="100%">
</p>

<p align="center">
  <img src="Images/showcase2.png" alt="Pet Beacon showcase screen 2" width="100%">
</p>

<!-- ## Main Features

### 1. Authentication and Profile

- Firebase Authentication for registration and login
- Firestore-based profile storage
- Pet name and pet type configuration

### 2. BLE Tracking

- BLE discovery using `flutter_blue_plus`
- Device selection from nearby scan results
- Stable list ordering to reduce scan-list jumping
- RSSI threshold control for proximity classification
- Smoothed `Far` detection based on recent BLE samples

### 3. Camera Integration

- Local TimerCAM service detection
- Health check endpoint support
- Manual test capture from the `Device` page
- Automatic capture when BLE state enters `Far`
- Immediate local UI update, with Firestore used only as background backup

### 4. Multi-Page App Structure

- `Home`: current pet state and last automatic capture
- `History`: last seen information and capture events
- `Device`: camera endpoint, manual capture, and RSSI threshold controls
- `BLE`: scan, select, and debug nearby BLE devices -->

## Project Overview

Pet Beacon is built around a simple idea: use a BLE tag as a proximity signal for a pet, and combine it with a local camera board so that the owner can react when the pet moves farther away.

The current version supports:

- Firebase email and password authentication
- Firestore-backed user profile storage
- Pet profile setup with pet name and pet type
- BLE scanning and nearby device selection
- RSSI-based state mapping for `Very Close`, `Nearby`, and `Far`
- Automatic image capture when the selected BLE device enters `Far`
- Manual camera test capture from the app
- Camera service health detection on the local network
- History and last-seen style review screens


## Core Workflow

1. The user signs in and sets up a pet profile.
2. The app scans nearby BLE devices on the `BLE` page.
3. The user selects one BLE device as the tracking source.
4. The app maps RSSI values into proximity states.
5. When the selected device moves into `Far`, the app triggers a local camera capture.
6. The latest image and event details appear in the app history and last-seen views.

## Screens and Interaction Notes

### Home

- Displays the current pet status
- Shows the latest automatic capture when available
- Supports prototype state simulation when no live BLE device is selected

### History

- Displays recent capture events
- Shows the latest image and environment summary

### Device

- Displays the current camera endpoint
- Provides `Detect Camera Service`
- Provides `Test Camera Capture`
- Lets the user tune the RSSI threshold

### BLE

- Scans nearby BLE devices
- Lets the user choose one active tracking device
- Provides a `Clear Device` action to return to prototype mode

## Hardware and Firmware

The current active camera firmware is in:

- `esp32/imercam_x/`

Other earlier experiments are kept in:

- `esp32/petracker/`
- `raspberry_pi/petcam/`

The active TimerCAM firmware currently supports:

- local HTTP health checks
- single-frame JPEG capture
- MJPEG stream preview
- BLE advertising name configuration
- local network integration for the Flutter app

## Repository Structure

- `lib/main.dart` - main Flutter UI, BLE workflow, and camera integration
- `lib/firebase_options.dart` - Firebase platform configuration
- `pubspec.yaml` - Flutter dependencies and app version
- `Images/` - storyboard, showcase screenshots, and research visuals used in the README
- `esp32/imercam_x/` - active M5Stack TimerCAM firmware used by the current prototype
- `esp32/petracker/` - earlier ESP32-CAM prototype retained for reference
- `raspberry_pi/petcam/` - earlier Raspberry Pi camera prototype retained for reference


## Installation

### Flutter App

1. Clone the repository.
2. Run:

```bash
flutter pub get
```

3. Ensure Firebase config files are present for your target platform.
4. Connect a physical mobile device with Bluetooth enabled.
5. Start the app:

```bash
flutter run
```

### TimerCAM Firmware

1. Open `esp32/imercam_x/` in PlatformIO.
2. Build and upload the firmware to the TimerCAM board.
3. Connect the board to the same Wi-Fi network as the phone.
4. Confirm the following endpoints are reachable:

```text
http://<camera-ip>/health
http://<camera-ip>/capture-meta
http://<camera-ip>/stream
```

5. In the Flutter app, open the `Device` page and run `Detect Camera Service`.

## Current Limitations

- RSSI is only a rough proxy for physical distance
- BLE detection can still vary with environment and device orientation
- Camera capture reliability depends on the local board and Wi-Fi stability

## Future Work

- Add flash or low-light support so the camera can still capture usable images in dark environments.
- Explore a 360-degree camera setup to provide richer visual context when a single fixed view is not distinctive enough.
- Integrate GPS-based location tracking for more precise real-time pet positioning beyond BLE proximity alone.

## Contact

- Email: huangty393@gmail.com
