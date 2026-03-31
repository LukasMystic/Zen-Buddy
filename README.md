# Rapport: AR Virtual Companion

An augmented reality application designed to provide a calming, low-stakes spatial distraction to help users manage stress and practice emotional grounding. Built entirely utilizing native Apple frameworks, the application brings a lifelike, interactive virtual companion into the user's physical environment.

## Overview

The initial challenge was to create a memorable experience using technology. While repetition builds habits, it is the interruption of patterns that creates memories. Research indicates that emotional regulation and stress recovery require shifting the body out of "fight-or-flight" mode. 

By leveraging cognitive grounding techniques, this application serves as an active distraction that requires just enough focus to pull attention away from overwhelming emotions without causing additional cognitive load.

## Key Features

* **Spatial Integration:** Utilizes world tracking and horizontal plane detection to accurately anchor a 3D computational model into the physical environment. Includes automatic environment texturing for realistic lighting and drop shadows.
* **Tactile Interactions:** Implements native gesture recognizers allowing users to tap to interact, pinch to scale, and pan to rotate the companion. Interaction generates rigid and medium haptic feedback to simulate physical touch.
* **Voice Recognition:** Integrates live audio transcription to allow users to interact with the companion using customized verbal commands.
* **Immersive Audio:** Features smooth, mathematically cross-faded ambient music and contextual sound effects to create a peaceful environment without jarring auditory transitions.
* **Minimalist Interface:** Employs a frosted-glass (glassmorphism) layout overlaid on the camera feed to maintain complete focus on the AR space and reduce visual clutter.

## Technical Architecture

The application was built exclusively using native Apple SDKs:

* **SwiftUI:** Serves as the primary structural framework, driving the reactive 2D interface and managing complex state transitions smoothly.
* **ARKit:** Handles spatial computing inputs, providing device tracking, plane detection, and environmental light estimation.
* **RealityKit:** Acts as the 3D rendering engine, responsible for managing `.usdz` assets, skeletal animations, and dynamic geometry generation.
* **UIKit:** Bridged into the SwiftUI environment to handle touch lifecycle events via Gesture Recognizers and physical responses via `UIImpactFeedbackGenerator`.
* **AVFoundation:** Manages the playback layer for seamless architectural audio manipulation and background loops.
* **Speech:** Captures microphone input and processes natural language parsing to trigger state changes based on specific keywords.

## Human Interface Guidelines (HIG) Application

The application closely follows Apple's design principles:

* **Aesthetic Integrity:** The application’s appearance directly supports its function. By utilizing a minimalist, translucent UI and smooth cross-faded animations, the interface communicates a peaceful, low-stress environment without overwhelming the user.
* **Feedback:** The app provides immediate auditory, visual, and tactile feedback to user actions, anchoring them in reality. Physical haptics accurately mirror the virtual interactions, fulfilling the cognitive grounding requirements of the project.

## Requirements

* iOS 17.0+
* Xcode 15.0+
* A physical iOS device with a rear-facing camera and microphone (ARKit and Speech features are not fully supported on the iOS Simulator).

