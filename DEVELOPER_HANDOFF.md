# TRACER - Professional Golf Shot Tracking App

## 🏌️ Overview

A premium iOS app for live golf shot tracing, inspired by The Masters' prestigious aesthetic and SmoothSwing's functionality.

**Key Features:**
- Live shot tracing during recording
- High frame rate capture (240fps) for reliable detection
- Masters-inspired premium UI
- Pro subscription tier ready

---

## 🧪 TESTING THE APP

### Quick Start Testing

1. **Open the project in Xcode:**
```bash
open /Users/seth/TRACER/IdentifyingBallTrajectoriesinVideo.xcodeproj
```

2. **Add test video to Simulator:**
   - Find a golf swing video (YouTube, or your own)
   - Download it as .mov or .mp4
   - Drag the file onto the iOS Simulator window
   - It will be saved to Photos

3. **Run the app in Simulator:**
   - Select an iPhone 14 Pro or later simulator
   - Build and Run (⌘R)
   - You'll see the **Test Mode** button (since camera isn't available)

4. **Test the tracer:**
   - Tap "🧪 Open Test Mode"
   - Tap "⚡ Quick Load First Video" or select a video
   - Tap on the video to set the ball starting position
   - Tap "▶️ Process" to run the tracer
   - Watch trajectory detection in real-time!

### Test Mode Features

```
┌─────────────────────────────────────────────────────────────┐
│  🧪 TEST MODE                                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  [Video Preview]                                            │
│       🎯 ← Tap to set ball position                        │
│                                                             │
│  Progress: ████████░░░░ 65%                                │
│                                                             │
│  [📹 Load Video]  [▶️ Process]                             │
│                                                             │
│  Debug Log:                                                 │
│  [10:23:45] 📹 Video loaded: 1920x1080 @ 60fps             │
│  [10:23:48] 🎯 Ball position set: (0.42, 0.85)             │
│  [10:23:50] ▶️ Starting processing...                       │
│  [10:23:55] 📈 Trajectory: 47 points detected              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Testing on Real Device

1. Connect your iPhone
2. Set up code signing in Xcode
3. Build and Run
4. Use the alignment screen to position yourself
5. Record a real golf shot!

---

## 🎨 Brand Identity (Masters-Inspired)

### Color Palette

| Color | Hex | Usage |
|-------|-----|-------|
| **Masters Green** | `#006747` | Primary brand, key actions |
| **Championship Gold** | `#C9A227` | Accent, premium elements, default tracer |
| **Background** | `#0A0A0A` | App background |
| **Surface** | `#141414` | Cards, elevated elements |

### Typography
- **Headlines**: Georgia Bold (classic, prestigious)
- **Body**: SF Pro (clean, readable)
- **Metrics**: SF Mono (stats display)

---

## 🔧 Technical Architecture

### Core Insight: HIGH FRAME RATE

```
240fps vs 60fps Ball Detection:
┌──────────┬───────────────┬────────────────┐
│ FPS      │ Ball Movement │ Detection      │
├──────────┼───────────────┼────────────────┤
│ 60fps    │ ~4 feet/frame │ Very Hard      │
│ 240fps   │ ~1 foot/frame │ Easy!          │
└──────────┴───────────────┴────────────────┘

Record @ 240fps → Track @ 240fps → Export @ 30fps
```

### Silhouette = Ball Position (No Tap Required!)

The silhouette overlay has a **fixed ball position marker**. When users align themselves with the silhouette, the ball is automatically at the known position. No tapping required!

---

## 📁 File Structure

```
/ShotTracer/
├── CameraManager.swift           # 240fps capture
├── HighFrameRateBallTracker.swift # Ball tracking
├── ShotSessionController.swift   # Main controller
├── ShotExporter.swift           # Video export
├── TrajectoryDetector.swift     # Vision backup
├── TrajectoryModel.swift        # Data models
├── LiveShotDetector.swift       # Impact detection
├── CoordinateUtilities.swift    # Coordinates
│
├── UI/
│   ├── DesignSystem.swift        # Masters styling
│   ├── PremiumShotViewController.swift
│   ├── PremiumAlignmentViewController.swift
│   ├── PremiumReviewViewController.swift
│   ├── RecordingControlsView.swift
│   ├── GolferSilhouetteView.swift
│   ├── GlowingTracerView.swift
│   ├── SettingsViewController.swift
│   └── OnboardingViewController.swift
│
└── Debug/                        # DEBUG builds only
    ├── TestVideoProcessor.swift  # Process videos for testing
    └── TestModeViewController.swift # Test UI
```

---

## 🔄 App Flow

```
1. ONBOARDING (first launch)
   └── Premium, branded welcome screens

2. ALIGNMENT
   └── User aligns with silhouette
   └── Ball position is FIXED (no tap!)
   └── "Lock In" → Ready to record

3. RECORDING @ 240fps
   └── High frame rate capture
   └── Pose detection monitors for impact
   └── On IMPACT → Start ball tracking

4. LIVE TRACKING
   └── Ball moves ~1 foot/frame (easy!)
   └── Simple white blob detection
   └── Real-time tracer displayed

5. EXPORT @ 30fps
   └── Downsample video
   └── Same trajectory data
   └── Save to Photos / Share

6. REVIEW
   └── Play back with tracer
   └── View metrics
   └── Share to social
```

---

## 📱 Device Requirements

| Device | Frame Rate | Experience |
|--------|-----------|------------|
| iPhone 12 Pro+ | 240fps | **Best** |
| iPhone 11+ | 120fps | Good |
| iPhone X+ | 60fps | Basic |

---

## 🚀 Future: Pro Subscription

The UI is designed to support:
- User authentication
- Pro tier features (more tracer colors, export quality, etc.)
- Gold "PRO" badges on premium features
- Subscription management

### Pro Feature Ideas
- Unlimited exports
- 4K export quality
- Advanced tracer styles
- Shot analytics & history
- Cloud backup
- Remove watermark

---

## ⚠️ Important: Adding Debug Files to Xcode

The Debug folder files need to be added to the Xcode project:

1. Open the project in Xcode
2. Right-click on the `ShotTracer` folder in the navigator
3. Select "Add Files to IdentifyingBallTrajectoriesinVideo..."
4. Navigate to `ShotTracer/Debug/`
5. Select both files and click "Add"

Or add them via the project navigator by dragging the Debug folder into the ShotTracer group.

---

## ✅ Success Criteria

1. ✅ Masters-inspired premium UI
2. ✅ Camera runs at 240fps
3. ✅ Silhouette defines ball position
4. ✅ Impact triggers tracking
5. ✅ Live tracer matches export
6. ✅ Clean, focused codebase
7. ✅ Test mode for development
8. ✅ Ready for subscription features

---

*Built with precision. Designed for champions.*
