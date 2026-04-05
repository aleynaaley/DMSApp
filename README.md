# Vigilance — Driver Drowsiness Detection

<p align="center">
  <img src="docs/banner.png" alt="Vigilance App" width="800"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2017%2B-black?style=flat-square&logo=apple"/>
  <img src="https://img.shields.io/badge/swift-5.9-orange?style=flat-square&logo=swift"/>
  <img src="https://img.shields.io/badge/CoreML-BiLSTM-blue?style=flat-square"/>
  <img src="https://img.shields.io/badge/Vision-Face%20Landmarks-green?style=flat-square"/>
  <img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square"/>
</p>

> **Real-time driver fatigue detection on-device using a hybrid BiLSTM + rule-based system — no server, no internet required.**

---

## Overview

Vigilance is an iOS application that monitors driver drowsiness in real-time using the front-facing camera. It combines a trained **Bidirectional LSTM** neural network with a **rule-based engine** grounded in peer-reviewed research to detect:

- 👁️ Eye closure and blink patterns (PERCLOS)
- 🥱 Yawning frequency
- 😴 Microsleep events (>1.5s eye closure)
- 📐 Head pose deviation

All inference runs **on-device** via CoreML — no data leaves the phone.

---

## Demo

| Normal Driving | Drowsy Detection | Alert |
|---|---|---|
| ![safe](docs/safe.gif) | ![drowsy](docs/drowsy.gif) | ![alert](docs/alert.gif) |

---

## Features

- **Personalized calibration** — Two-phase baseline per driver profile
  - Phase 1: Eye aspect ratio (EAR) at rest
  - Phase 2: Mouth aspect ratio (MAR) during natural speech → prevents false yawn triggers while talking or singing
- **Hybrid decision engine** — BiLSTM model score + rule-based signals combined
- **Automatic alerts** — Sound + vibration, auto-dismiss after 5s, re-triggers if condition persists
- **Multi-profile support** — Each driver has their own baseline and session history
- **Session analytics** — Safety score, yawn count, microsleep count, PERCLOS over time
- **Zero network dependency** — Fully offline, privacy-preserving

---

## Architecture

```
Camera Frame (AVFoundation)
        │
        ▼
Face Landmark Detection (Vision — VNDetectFaceLandmarksRequest)
        │
        ├──► EAR  (Eye Aspect Ratio)
        ├──► MAR  (Mouth Aspect Ratio)
        └──► Head Pose (Pitch / Yaw / Roll)
                │
                ▼
         FeatureBuffer
    (51 features, sliding window)
                │
        ┌───────┴────────┐
        ▼                ▼
   BiLSTM Model      RuleEngine
  (CoreML, 30-frame  (PERCLOS, yawn
    sequence)         counter, closure)
        │                │
        └───────┬────────┘
                ▼
         Hybrid Decision
      (safe / caution / warning / critical)
                │
                ▼
           DrivingView UI + Alert
```

---

## ML Model

### Architecture
- **Type:** Bidirectional LSTM (BiLSTM)
- **Input:** `(1, 30, 51)` — 30-frame window × 51 features
- **Output:** `drowsiness_prob` — sigmoid probability [0, 1]
- **Hidden size:** 128 × 2 (bidirectional)
- **Format:** CoreML `.mlpackage` (ML Program)

### Features (51 total)
| Category | Features |
|---|---|
| Raw signals | `ear`, `mar`, `pitch`, `yaw`, `roll` |
| Baseline-normalized | `ear_ratio`, `ear_diff`, `mar_ratio`, `mar_diff`, `delta_pitch/yaw/roll` |
| Temporal means | `ear/mar/pitch/yaw/roll_mean_1s/5s/10s` |
| PERCLOS | `perclos_5s`, `perclos_10s` |
| Blink | `blink_start`, `blink_count_5s`, `blink_rate_5s` |
| Variability | `ear_std_5s`, `mar_std_5s` |
| Velocity | `ear_velocity`, `pitch_velocity`, `yaw_velocity` |

### Training
```
Dataset:    Custom collected + YawDD augmentation
Optimizer:  Adam (lr=1e-3)
Loss:       BCEWithLogitsLoss (class-weighted)
Window:     30 frames @ ~30fps = ~1 second context
```

---

## Rule Engine — Decision Thresholds

All thresholds are grounded in peer-reviewed literature:

| Signal | Threshold | Source |
|---|---|---|
| **PERCLOS** | > 15% over 60s | Abe T. (2023). *SLEEP Advances*, 4(1). [doi](https://doi.org/10.1093/sleepadvances/zpad006) |
| **Critical eye closure** | > 1.5 seconds | Murata A. et al. (2022). *IEEE Access*, 10, 70806–70814. [doi](https://doi.org/10.1109/ACCESS.2022.3187995) |
| **Yawn frequency** | ≥ 3 in 5 minutes | Abtahi M. et al. (2014). *YawDD*. ACM MMSys. |
| **EAR closed threshold** | EAR < baseline × 0.75 | Soukupova & Cech (2016). *CVWW 2016*. |
| **MAR yawn threshold** | MAR > speech_baseline × 1.5 | Abtahi M. et al. (2014). *YawDD*. |
| **Model threshold** | score ≥ 0.5 | Graves & Schmidhuber (2005). *IJCNN 2005*. |
| **Hybrid superiority** | rule + model combined | Ngxande M. et al. (2017). *Pattern Recognition Letters*, 91. |

### Decision Logic

```
if eye_closure >= 1.5s                   → CRITICAL  (alert immediately)
if model_score >= 0.5 AND rules_fired    → WARNING   (alert)
if 2+ rules_fired                        → WARNING   (alert)
if 1 rule_fired                          → CAUTION   (no alert, visual only)
if model_score >= 0.5 only              → CAUTION   (no alert)
else                                     → SAFE
```

> **Warmup:** No alerts during the first 30 frames (~1s) — feature windows are not yet stable.

---

## Two-Phase Calibration

Each driver profile requires a one-time calibration that is saved and reused on subsequent sessions.

```
Phase 1 (5s) — Eye Baseline
  Driver looks straight at camera, mouth closed
  → Records median EAR → sets eye-close threshold

Phase 2 (5s) — Mouth Baseline
  Driver reads on-screen text aloud at natural pace
  → Records median MAR during speech
  → Yawn threshold = speech_MAR × 1.5
  → Normal talking / singing does NOT trigger yawn detection
```

---

## Project Structure

```
DriverBehaviorSystem/
├── App/
│   ├── DriverBehaviorSystemApp.swift
│   └── ContentView.swift
├── Engine/
│   ├── DrowsinessEngine.swift      # Main coordinator, CoreML inference
│   ├── FeatureBuffer.swift         # Real-time 51-feature computation
│   └── RuleEngine.swift            # Hybrid rule-based decision engine
├── Models/
│   ├── AppStore.swift              # App-wide state
│   ├── DrivingSession.swift        # Session data model
│   └── UserProfile.swift           # Driver profile
├── Views/
│   ├── Welcome/
│   │   └── WelcomeView.swift
│   ├── Calibration/
│   │   └── CalibrationView.swift
│   ├── Driving/
│   │   ├── DrivingView.swift
│   │   └── CameraManager.swift
│   └── Analytics/
│       └── AnalyticsView.swift
└── Resources/
    └── DrowsinessModel.mlpackage
```

---

## Requirements

| Requirement | Version |
|---|---|
| iOS | 17.0+ |
| Xcode | 15.0+ |
| Swift | 5.9+ |
| Device | iPhone with front camera (Face ID generation recommended) |

> **Note:** CoreML inference uses Neural Engine when available (A12 Bionic+). The app runs on simulator but camera features require a physical device.

---

## Setup

```bash
# Clone
git clone https://github.com/yourusername/vigilance-ios.git
cd vigilance-ios

# Open in Xcode
open DriverBehaviorSystem.xcodeproj
```

1. Select your development team in **Signing & Capabilities**
2. Connect a physical iPhone
3. Build & Run (`⌘R`)

> The `DrowsinessModel.mlpackage` is included in the repository. To retrain or export your own model, see [`convert_coreml.py`](convert_coreml.py).

---

## Model Export (Optional)

To retrain and re-export the CoreML model:

```bash
cd /path/to/training
source venv/bin/activate
pip install torch coremltools numpy

python convert_coreml.py
```

The script embeds normalization (mean/std) inside the model graph — the iOS app sends raw features without manual normalization.

---

## References

```
Abe T. (2023). PERCLOS-based technologies for detecting drowsiness.
  SLEEP Advances, 4(1), zpad006. https://doi.org/10.1093/sleepadvances/zpad006

Murata A. et al. (2022). Sensitivity of PERCLOS70 to drowsiness levels.
  IEEE Access, 10, 70806–70814. https://doi.org/10.1109/ACCESS.2022.3187995

Abtahi M. et al. (2014). YawDD: Yawning Detection Dataset.
  Proceedings of the 5th ACM Multimedia Systems Conference (MMSys '14).

Soukupova T. & Cech J. (2016). Real-Time Eye Blink Detection using Facial Landmarks.
  Computer Vision Winter Workshop (CVWW 2016).

Graves A. & Schmidhuber J. (2005). Framewise phoneme classification with
  bidirectional LSTM networks. IJCNN 2005.

Ngxande M. et al. (2017). Driver drowsiness detection using behavioral measures
  and machine learning: A review of state-of-the-art techniques.
  Pattern Recognition Letters, 91, 113–121.
```

---

## License

```
MIT License — see LICENSE file for details.
```

---

<p align="center">
  Built with ❤️ · CoreML · Vision · SwiftUI
</p>
