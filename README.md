# Oasis

Oasis is a Nigerian prop-tech platform focused on secure, fraud-free rentals. This is the Lean MVP build.

## Run the V2 short-stay preview

Install Flutter with Dart 3.11.1 or newer, then clone the V2 branch and launch its preview:

```sh
git clone --branch v2-shortlets https://github.com/mofixiu/oasis.git
cd oasis
flutter pub get
flutter run -t tool/v2_preview_main.dart
```

The preview opens as a sample guest and uses fixture data, so it does not need backend credentials. Photos are optional; without a photo directory, the app uses its bundled sample images. To use local preview photos, pass their absolute directory:

```sh
flutter run -t tool/v2_preview_main.dart \
  --dart-define=PREVIEW_PHOTOS=/absolute/path/to/photos
```

To choose a simulator or device, list available targets with `flutter devices`, then add `-d <device-id>` to the `flutter run` command. iOS Simulator requires Xcode; Android Emulator requires Android Studio and an installed emulator.

## Architecture
- **Pattern:** Feature-First MVCS (Model-View-Controller-Service)
- **State Management:** Provider
- **Mock Data Strategy:** All services use the Repository Pattern. We currently use `Mock` services that simulate network latency (2 seconds) and return hardcoded, realistic dummy data. Controllers depend *only* on abstract interfaces.

## Folder Structure
```text
/lib
  /core         (themes, constants, routing, generic widgets)
  /features
    /auth       (models, views, controllers, services)
    /agreements
    /payments
    /dashboard
```

## Theme Colors
- **Primary (Deep Navy):** `#0A192F`
- **Secondary (Emerald Green):** `#10B981`
- **Action (Electric Blue):** `#3B82F6`
- **Warning (Amber):** `#F59E0B`
- **Background (Soft Grey):** `#F8FAFC`
