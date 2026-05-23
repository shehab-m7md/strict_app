<div align="center">

# 📱 STRICT
### Parental Monitoring Application


**Suez University — Faculty of Computers and Information**  
**Graduation Project · Academic Year 2025–2026**

*Supervised by Dr. Fatma Said Abousaleh*

---

</div>

## 📋 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [System Architecture](#-system-architecture)
- [How It Works](#-how-it-works)
- [Tech Stack](#-tech-stack)
- [Project Structure](#-project-structure)
- [Firebase Schema](#-firebase-schema)
- [Android Permissions](#-android-permissions)
- [Setup & Installation](#-setup--installation)
- [Configuration](#-configuration)
- [Team](#-team)

---

## 🧭 Overview

**Strict** is an Android parental monitoring application that runs as a background foreground service, capturing and classifying screen content every 15 seconds using an on-device TensorFlow Lite NSFW detection model. At the end of each day it generates a structured report — covering activity gaps, detected NSFW sequences, and app usage statistics — and delivers it to designated watchers through Firebase Firestore and OneSignal push notifications.

### Design Philosophy

| Principle | Implementation |
|-----------|---------------|
| **Automation** | Zero ongoing manual operation after setup — capture, classify, report, and upload happen automatically |
| **Privacy** | Raw screen captures are processed entirely on-device and never transmitted to any server |
| **Structure** | Concise daily reports highlight events of concern instead of dumping raw data |

---

## ✨ Key Features

- **Background Screen Capture** — MediaProjection API captures frames every 15 seconds, surviving Doze mode via `AlarmManager.setExactAndAllowWhileIdle()`
- **On-Device NSFW Detection** — MobileNet-family TFLite model with a three-pass vertical inference strategy; no sensitive data ever leaves the device
- **Automated Daily Reports** — Gap analysis, NSFW event grouping (2+ consecutive frames), protected content detection, and UsageStats-based app usage summary
- **Cloud Report Distribution** — Firebase Firestore delivers reports to each authorised watcher; raw log also uploaded for full audit trail
- **Push Notifications** — OneSignal REST API notified per watcher on every new report; localised Arabic/English
- **Consent-Based Monitoring** — Monitoring relationships require explicit acceptance by the monitored user; both parties can terminate at any time
- **Boot Persistence** — BootReceiver records reboot timestamps and notifies the user to restart monitoring; reboot events are retroactively injected into the log
- **Single-Device Enforcement** — FCM token checked on every startup; mismatched token forces sign-out to prevent multi-device bypass
- **Full Localisation** — Complete Arabic and English support via Easy Localization

---

## 🏗 System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      FLUTTER LAYER  (Dart)                       │
│  UI · State Management · Firebase Auth SDK · Firestore streams   │
│                                                                  │
│  login  sign_up  home_page  watched_users  reports  profile …    │
│                                                                  │
│              monitor_service.dart  (IPC bridge)                  │
│         MethodChannel ◄──────────────► EventChannel              │
└─────────────────────┬────────────────────────┬───────────────────┘
                      │  com.ShehabTeam.strict  │
┌─────────────────────▼────────────────────────▼───────────────────┐
│                    KOTLIN LAYER  (Android)                        │
│                                                                  │
│  MainActivity ── stores MediaProjection token                    │
│  CaptureService ── Foreground Service                            │
│    │  MediaProjection VirtualDisplay → ImageReader               │
│    │  TFLite 3-pass inference (224×224 per section)              │
│    │  Log file writer · Report generator                         │
│    └─ AlarmScheduler → AlarmReceiver → triggerCapture()          │
│                                                                  │
│  BootReceiver ── records reboot timestamps                       │
│  UploadReportWorker ── WorkManager CoroutineWorker               │
│    └─ uploads log_files/ · writes reports/ · OneSignal notify    │
└───────────────────────────────────┬──────────────────────────────┘
                                    │  HTTPS
                    ┌───────────────▼───────────────┐
                    │       Firebase Cloud           │
                    │  Firestore · Auth · FCM        │
                    │  + OneSignal Push Platform     │
                    └───────────────────────────────┘
```

---

## ⚙️ How It Works

### The Five-Stage Pipeline

```
① CAPTURE          ② COMPLETED/        ③ REPORT GEN       ④ REPORTED/        ⑤ FIRESTORE
──────────         ──────────────       ────────────        ──────────         ─────────────
Every 15s          At midnight          buildReport()       WorkManager        log_files/
AlarmReceiver  →   markOldLogs      →   parses all      →   picks up       →   reports/watcher
TFLite 3-pass      AsComplete()        entries             uploads            OneSignal notify
writes to log      moves file to        appends ===                            watcher sees card
                   Completed/           markers
```

### Log Entry Format

Each capture event writes one line:

```
HH:mm:ss | Battery: 84% | App: com.android.chrome | NSFW 87.3%
HH:mm:ss | Battery: 83% | App: com.example.video  | NORMAL
HH:mm:ss | Battery: 83% | App: SYSTEM             | Service started
```

**Classification results:** `NORMAL` · `NSFW XX.X%` · `PROTECTED` · `SCREEN_OFF - SKIPPED` · `NO_FRAME` · `FAILED`

### Report Sections

| Section | Content |
|---------|---------|
| **Header** | Date, device model and Android version |
| **⚠️ Gaps** | Service interruptions > 2 minutes, labelled by cause (user stop / logout / system kill / reboot / unexplained) |
| **🔴 NSFW sequences** | Groups of 2+ consecutive NSFW frames — app name, start/end time, duration |
| **🔒 Protected** | Groups of 2+ consecutive protected-screen frames |
| **✅ Clean / App usage** | No issues found + top-15 apps by foreground time from UsageStatsManager |

### NSFW Detection

The TFLite model receives a 224 × 224 RGB float32 input and outputs a 2-class softmax `[safe, nsfw]`. Each captured frame is split into **three equal vertical sections**; each section is independently inferred and the **maximum NSFW score** across the three is used. Threshold: **0.75 (75%)**.

> A consecutive-frame filter suppresses isolated false positives: only sequences of 2+ consecutive NSFW-classified frames appear in the report.

---

## 🛠 Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| UI Framework | Flutter (Dart) | 3.x |
| Background Engine | Kotlin (Android) | JVM 17 |
| Build | compileSdk 36, minSdk 26 (Android 8.0) | — |
| Cloud Database | Firebase Firestore | BOM 32.7.0 |
| Authentication | Firebase Auth | BOM 32.7.0 |
| Push Notifications | OneSignal | REST API v1 |
| ML Inference | TensorFlow Lite | latest stable |
| Background Work | WorkManager | 2.9.0 |
| HTTP Client | OkHttp | 4.12.0 |
| Localisation | Easy Localization | AR + EN |
| Alarm | AlarmManager (exact, Doze-aware) | — |

---

## 📁 Project Structure

```
strict/
│
├── lib/                                # Flutter / Dart source
│   ├── main.dart                       # App entry, routing, OneSignal init
│   ├── home_page.dart                  # Monitoring toggle, permission checklist, drawer
│   ├── login_page.dart                 # Email + password auth
│   ├── sign_up.dart                    # Registration, custom ID, avatar selection
│   ├── email_verification_page.dart    # Polls Firebase Auth until verified
│   ├── forgot_password.dart            # Password reset email
│   ├── watched_users_page.dart         # List of monitored users + report previews
│   ├── reports_page.dart               # Full report viewer per user
│   ├── log_file_page.dart              # Raw log content from Firestore
│   ├── requests.dart                   # Incoming monitoring requests
│   ├── my_requests.dart                # Outgoing monitoring requests
│   ├── watch_you.dart                  # Who watches this user
│   ├── you_watch.dart                  # Search + send monitoring request
│   ├── profile.dart                    # Account settings, avatar, password change
│   ├── monitor_service.dart            # MethodChannel + EventChannel IPC bridge
│   ├── auth_service.dart               # Firebase Auth helper
│   └── notification_service.dart       # Local notification helpers
│
├── android/app/src/main/java/
│   └── com/ShehabTeam/strict/
│       ├── MainActivity.kt             # Flutter-Kotlin bridge, MediaProjection token store
│       ├── CaptureService.kt           # Core foreground service — capture, infer, log, report
│       ├── UploadReportWorker.kt       # WorkManager worker — upload + notify
│       ├── AlarmScheduler.kt           # Schedules exact 15-second alarm
│       ├── AlarmReceiver.kt            # Receives alarm, triggers capture or logs kill
│       └── BootReceiver.kt             # Records reboot timestamp, shows notification
│
├── assets/
│   ├── animations/                     # Lottie animation files
│   ├── images/profile/                 # Avatar images (2–9.jpg)
│   ├── translations/
│   │   ├── en.json                     # English strings
│   │   └── ar.json                     # Arabic strings
│   └── nsfw_inference.tflite           # TFLite NSFW binary classifier
│
└── android/app/
    ├── google-services.json            # Firebase project config (not committed)
    ├── AndroidManifest.xml             # Permissions, receivers, services
    └── build.gradle.kts                # compileSdk 36, minSdk 26
```

---

## 🗄 Firebase Schema

```
Firestore/
├── users/{uid}
│   ├── email, displayName, customId, avatarIndex
│   ├── appLocale            ← "en" | "ar" for localised notifications
│   ├── createdAt
│   └── reports/{customId}_{date}
│       ├── targetCustomId, reportText, logFileId
│       ├── reportDate, createdAt
│       └── [read: watcher only · create: relation must exist]
│
├── log_files/{customId}_{date}
│   ├── content              ← full raw log + report between === markers
│   ├── uploadedBy, date, createdAt
│   └── [write-once: update and delete disabled]
│
├── monitoring_relations/{fromUid}_{toUid}
│   ├── fromUserId, toUserId, requestId, createdAt
│   └── [read: members only · created by batch on request accept]
│
├── monitoring_requests/{fromUid}_{toUid}
│   ├── fromUserId, toUserId, status (pending→accepted|rejected)
│   ├── type, seenByTo, seenByFrom, createdAt, acceptedAt
│   └── [update: toUserId only · delete: requester only]
│
└── custom_ids/{customId}
    ├── uid, createdAt
    └── [uniqueness lookup — doc ID enforces global uniqueness]
```

### Security Rules Summary

| Collection | Read | Create | Update | Delete |
|---|---|---|---|---|
| `users` | Public | Own UID | Own UID | Own UID |
| `users/*/reports` | Watcher only | Relation exists | ✗ | Watcher only |
| `log_files` | Any auth user | uploadedBy = UID | **✗ disabled** | **✗ disabled** |
| `monitoring_relations` | Members only | Via batch (server) | ✗ | Members only |
| `monitoring_requests` | Parties only | fromUid = auth | toUid only | Requester only |
| `custom_ids` | Public | Auth required | ✗ | ✗ |

---

## 🔐 Android Permissions

| Permission | Purpose |
|-----------|---------|
| `FOREGROUND_SERVICE` | Run CaptureService as foreground service |
| `FOREGROUND_SERVICE_MEDIA_PROJECTION` | Android 14+ media projection type |
| `MEDIA_PROJECTION` | Screen capture (runtime grant via dialog) |
| `PACKAGE_USAGE_STATS` | App usage reporting via UsageStatsManager |
| `RECEIVE_BOOT_COMPLETED` | Activate BootReceiver on device startup |
| `WAKE_LOCK` | `PARTIAL_WAKE_LOCK` to keep CPU alive during capture |
| `INTERNET` | Firestore, Firebase Auth, OneSignal API |
| `ACCESS_NETWORK_STATE` | WorkManager network constraint |
| `USE_EXACT_ALARM` | `setExactAndAllowWhileIdle` on Android 12+ |
| `SYSTEM_ALERT_WINDOW` | Overlay on some manufacturer ROMs |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Battery exemption request |

---

## 🚀 Setup & Installation

### Prerequisites

- Flutter SDK 3.x
- Android Studio Hedgehog / Iguana or later
- Kotlin JVM target 17
- A Firebase project with Firestore and Authentication enabled
- A OneSignal account with an Android app configured

### Steps

**1. Clone the repository**

```bash
git clone https://github.com/your-org/strict.git
cd strict
```

**2. Add Firebase configuration**

Place your `google-services.json` inside `android/app/`.

```
android/app/google-services.json
```

**3. Add the TFLite model**

Place `nsfw_inference.tflite` inside `assets/`:

```
assets/nsfw_inference.tflite
```

**4. Install Flutter dependencies**

```bash
flutter pub get
```

**5. Build and run**

```bash
flutter run --release
```

> ⚠️ The monitoring service requires a physical Android device. It does **not** work on emulators (MediaProjection permission is unavailable on most emulator configurations).

---

## ⚙️ Configuration

### OneSignal

In `lib/notification_service.dart` and `lib/main.dart`, replace the OneSignal App ID and API key with your own:

```dart
// notification_service.dart
static const _appId  = "YOUR_ONESIGNAL_APP_ID";
static const _apiKey = "YOUR_ONESIGNAL_REST_API_KEY";

// main.dart
OneSignal.initialize("YOUR_ONESIGNAL_APP_ID");
```

### Package Name

The Android package name is `com.ShehabTeam.strict`. To change it, update:
- `android/app/build.gradle.kts` → `applicationId`
- `android/app/src/main/AndroidManifest.xml`
- All `package com.ShehabTeam.strict` declarations in the Kotlin files
- The `CHANNEL` and `EVENT_CHANNEL` constants in `MainActivity.kt`

### NSFW Detection Threshold

The detection threshold is a single constant in `CaptureService.kt`:

```kotlin
// CaptureService.kt  →  analyzeNSFW()
return if (maxNSFW >= 0.75f)   // ← change this value
```

Increase to reduce false positives; decrease to increase sensitivity.

---

## 👥 Team

| Name 
|------
| Abd-Elrahman Alaa Mohamed Mahmoud
| Hassan Mohamed Elsayed Mohamed
| Mostafa Hany Mahmoud Ali
| Omar Mohamed Abd-Elradi
| Shehab Mohamed Abd-Elbaset
| Mohamed Yasser Mohamed

**Supervisor:** Dr. Fatma Said Abousaleh  
**Institution:** Suez University — Faculty of Computers and Information  
**Department:** Computer Science  

---

<div align="center">

**Suez University · Faculty of Computers and Information · 2025–2026**

</div>