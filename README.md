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
TÜRKÇE
---

# Vigilance — Sürücü Yorgunluk Tespiti

<p align="center">
  <img src="docs/banner.png" alt="Vigilance Uygulama" width="800"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2017%2B-black?style=flat-square&logo=apple"/>
  <img src="https://img.shields.io/badge/swift-5.9-orange?style=flat-square&logo=swift"/>
  <img src="https://img.shields.io/badge/CoreML-BiLSTM-blue?style=flat-square"/>
  <img src="https://img.shields.io/badge/Vision-Yüz%20Noktaları-green?style=flat-square"/>
  <img src="https://img.shields.io/badge/lisans-MIT-lightgrey?style=flat-square"/>
</p>

> **Hibrit BiLSTM + kural tabanlı sistem kullanarak gerçek zamanlı, cihaz üzerinde sürücü yorgunluğu tespiti — sunucu ve internet bağlantısı gerektirmez.**

---

## Genel Bakış

Vigilance, ön kamerayı kullanarak sürücü uykululuğunu gerçek zamanlı olarak izleyen bir iOS uygulamasıdır. Eğitilmiş bir **Çift Yönlü LSTM** sinir ağını, hakemli araştırmalara dayanan **kural tabanlı bir motorla** birleştirerek şunları tespit eder:

- 👁️ Göz kapanma ve kırpma örüntüleri (PERCLOS)
- 🥱 Esneme sıklığı
- 😴 Mikro uyku olayları (>1.5s göz kapanması)
- 📐 Baş pose sapması

Tüm çıkarım işlemi CoreML aracılığıyla **cihaz üzerinde** gerçekleşir — hiçbir veri telefonu terk etmez.

---

## Demo

| Normal Sürüş | Yorgunluk Tespiti | Uyarı |
|---|---|---|
| ![safe](docs/safe.gif) | ![drowsy](docs/drowsy.gif) | ![alert](docs/alert.gif) |

---

## Özellikler

- **Kişiselleştirilmiş kalibrasyon** — Her sürücü profili için iki aşamalı baseline
  - Faz 1: Dinlenik haldeki Göz En Boy Oranı (EAR)
  - Faz 2: Doğal konuşma sırasında Ağız En Boy Oranı (MAR) → konuşma veya şarkı söylerken yanlış esneme tetiklemesini önler
- **Hibrit karar motoru** — BiLSTM model skoru + kural tabanlı sinyaller birlikte değerlendirilir
- **Otomatik uyarılar** — Ses + titreme, 5s sonra otomatik kapanır, durum devam ederse yeniden tetiklenir
- **Çoklu profil desteği** — Her sürücünün kendi baseline'ı ve seans geçmişi vardır
- **Seans analitiği** — Güvenlik skoru, esneme sayısı, mikro uyku sayısı, zaman içinde PERCLOS
- **Sıfır ağ bağımlılığı** — Tamamen çevrimdışı, gizlilik koruyucu

---

## Mimari

```
Kamera Karesi (AVFoundation)
        │
        ▼
Yüz Landmark Tespiti (Vision — VNDetectFaceLandmarksRequest)
        │
        ├──► EAR  (Göz En Boy Oranı)
        ├──► MAR  (Ağız En Boy Oranı)
        └──► Baş Pose (Pitch / Yaw / Roll)
                │
                ▼
         FeatureBuffer
    (51 özellik, kayan pencere)
                │
        ┌───────┴────────┐
        ▼                ▼
   BiLSTM Modeli     Kural Motoru
  (CoreML, 30-frame  (PERCLOS, esneme
    sekans)           sayacı, kapanma)
        │                │
        └───────┬────────┘
                ▼
         Hibrit Karar
    (güvenli / dikkat / uyarı / kritik)
                │
                ▼
         DrivingView Arayüzü + Uyarı
```

---

## ML Modeli

### Mimari
- **Tür:** Çift Yönlü LSTM (BiLSTM)
- **Girdi:** `(1, 30, 51)` — 30 karelik pencere × 51 özellik
- **Çıktı:** `drowsiness_prob` — sigmoid olasılığı [0, 1]
- **Gizli boyut:** 128 × 2 (çift yönlü)
- **Format:** CoreML `.mlpackage` (ML Program)

### Özellikler (51 toplam)
| Kategori | Özellikler |
|---|---|
| Ham sinyaller | `ear`, `mar`, `pitch`, `yaw`, `roll` |
| Baseline-normalize | `ear_ratio`, `ear_diff`, `mar_ratio`, `mar_diff`, `delta_pitch/yaw/roll` |
| Zamansal ortalamalar | `ear/mar/pitch/yaw/roll_mean_1s/5s/10s` |
| PERCLOS | `perclos_5s`, `perclos_10s` |
| Kırpma | `blink_start`, `blink_count_5s`, `blink_rate_5s` |
| Değişkenlik | `ear_std_5s`, `mar_std_5s` |
| Hız | `ear_velocity`, `pitch_velocity`, `yaw_velocity` |

### Eğitim
```
Veri seti:  Özel toplanan + YawDD augmentation
Optimizer:  Adam (lr=1e-3)
Kayıp:      BCEWithLogitsLoss (sınıf ağırlıklı)
Pencere:    30 kare @ ~30fps = ~1 saniyelik bağlam
```

---

## Kural Motoru — Karar Eşikleri

Tüm eşikler hakemli literatüre dayandırılmıştır:

| Sinyal | Eşik | Kaynak |
|---|---|---|
| **PERCLOS** | 60s içinde > %15 | Abe T. (2023). *SLEEP Advances*, 4(1). [doi](https://doi.org/10.1093/sleepadvances/zpad006) |
| **Kritik göz kapanması** | > 1.5 saniye | Murata A. et al. (2022). *IEEE Access*, 10, 70806–70814. [doi](https://doi.org/10.1109/ACCESS.2022.3187995) |
| **Esneme sıklığı** | 5 dakikada ≥ 3 | Abtahi M. et al. (2014). *YawDD*. ACM MMSys. |
| **EAR kapanma eşiği** | EAR < baseline × 0.75 | Soukupova & Cech (2016). *CVWW 2016*. |
| **MAR esneme eşiği** | MAR > konuşma_baseline × 1.5 | Abtahi M. et al. (2014). *YawDD*. |
| **Model eşiği** | skor ≥ 0.5 | Graves & Schmidhuber (2005). *IJCNN 2005*. |
| **Hibrit üstünlüğü** | kural + model birlikte | Ngxande M. et al. (2017). *Pattern Recognition Letters*, 91. |

### Karar Mantığı

```
göz_kapanma >= 1.5s ise                      → KRİTİK   (hemen uyarı)
model_skoru >= 0.5 VE kurallar_tetiklendi ise → UYARI    (uyarı)
2+ kural tetiklendi ise                       → UYARI    (uyarı)
1 kural tetiklendi ise                        → DİKKAT   (uyarı yok, sadece görsel)
yalnızca model_skoru >= 0.5 ise              → DİKKAT   (uyarı yok)
aksi halde                                    → GÜVENLİ
```

> **Isınma süresi:** İlk 30 kare (~1s) boyunca uyarı verilmez — özellik pencereleri henüz stabil değildir.

---

## İki Aşamalı Kalibrasyon

Her sürücü profili, sonraki seanslar için kaydedilen ve yeniden kullanılan tek seferlik bir kalibrasyon gerektirir.

```
Faz 1 (5s) — Göz Baseline
  Sürücü ağzı kapalı şekilde kameraya düz bakar
  → Medyan EAR kaydedilir → göz kapanma eşiği belirlenir

Faz 2 (5s) — Ağız Baseline
  Sürücü ekrandaki metni doğal hızda yüksek sesle okur
  → Konuşma sırasındaki medyan MAR kaydedilir
  → Esneme eşiği = konuşma_MAR × 1.5
  → Normal konuşma / şarkı söyleme esneme tespitini TETİKLEMEZ
```

---

## Proje Yapısı

```
DriverBehaviorSystem/
├── App/
│   ├── DriverBehaviorSystemApp.swift
│   └── ContentView.swift
├── Engine/
│   ├── DrowsinessEngine.swift      # Ana koordinatör, CoreML çıkarımı
│   ├── FeatureBuffer.swift         # Gerçek zamanlı 51-özellik hesaplama
│   └── RuleEngine.swift            # Hibrit kural tabanlı karar motoru
├── Models/
│   ├── AppStore.swift              # Uygulama geneli durum
│   ├── DrivingSession.swift        # Seans veri modeli
│   └── UserProfile.swift           # Sürücü profili
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

## Gereksinimler

| Gereksinim | Sürüm |
|---|---|
| iOS | 17.0+ |
| Xcode | 15.0+ |
| Swift | 5.9+ |
| Cihaz | Ön kameralı iPhone (Face ID nesli önerilir) |

> **Not:** CoreML çıkarımı mevcut olduğunda Sinir Motoru'nu kullanır (A12 Bionic+). Uygulama simülatörde çalışır ancak kamera özellikleri fiziksel cihaz gerektirir.

---

## Kurulum

```bash
# Klonla
git clone https://github.com/yourusername/vigilance-ios.git
cd vigilance-ios

# Xcode'da aç
open DriverBehaviorSystem.xcodeproj
```

1. **Signing & Capabilities** bölümünden geliştirici ekibinizi seçin
2. Fiziksel bir iPhone bağlayın
3. Derle & Çalıştır (`⌘R`)

> `DrowsinessModel.mlpackage` depoya dahildir. Modeli yeniden eğitmek veya dışa aktarmak için [`convert_coreml.py`](convert_coreml.py) dosyasına bakın.

---

## Model Dışa Aktarma (İsteğe Bağlı)

CoreML modelini yeniden eğitmek ve dışa aktarmak için:

```bash
cd /path/to/training
source venv/bin/activate
pip install torch coremltools numpy

python convert_coreml.py
```

Script, normalizasyonu (mean/std) model grafiğinin içine gömer — iOS uygulaması manuel normalizasyon yapmadan ham özellikleri doğrudan gönderir.

---

## Kaynaklar

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

## Lisans

```
MIT Lisansı — ayrıntılar için LICENSE dosyasına bakın.
```

---

<p align="center">
  ❤️ ile yapıldı · CoreML · Vision · SwiftUI
</p>
