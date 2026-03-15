# Pet Beacon

Pet Beacon is a Flutter mobile app prototype for pet tracking. This repository contains the first mock-data version of the app for CASA0015 Mobile Systems & Interactions.

## Current Version

This version focuses on the first working app flow:

- Firebase email/password login and registration
- User profile creation in Firestore
- Pet profile setup with pet name and pet type
- A simple multi-page app structure
- Placeholder tracking, history, and device information screens

The current build is intended as an early functional prototype rather than a finished product.

## Main Idea

The app is designed around the idea of helping owners keep track of a pet tag and quickly view key information such as:

- owner and pet details
- last seen status
- recent history
- device or signal-related information

In this first version, some of the displayed content is still mock or placeholder data so that the interface and user flow can be tested before full integration.

## Tech Stack

- Flutter
- Dart
- Firebase Authentication
- Cloud Firestore

## Project Structure

- `lib/main.dart`: main application UI and flow
- `lib/firebase_options.dart`: Firebase platform configuration
- `android/` and `ios/`: platform-specific setup
- `web/`, `linux/`, `macos/`, `windows/`: generated platform folders

## Running the App

1. Install Flutter and the required platform tooling.
2. Run `flutter pub get`.
3. Make sure Firebase configuration files are available for your target platform.
4. Start the app with `flutter run`.

## Notes

- This repository represents the initial mock-data version of the app.
- The interface and structure are in place, but parts of the tracking experience still use placeholder content.
- Later versions can extend this with real device data, richer interaction, and more complete backend integration.
