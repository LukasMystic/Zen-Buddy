import SwiftUI
import RealityKit
import ARKit
import Combine
import Vision

enum DogAction: Int, CaseIterable, Identifiable {
    case standing = 0
    case sitting = 1
    case shake = 2
    case rollover = 3
    case playDead = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .standing: return "Standing"
        case .sitting: return "Sitting"
        case .shake: return "Shake"
        case .rollover: return "Rollover"
        case .playDead: return "Play Dead"
        }
    }

    var storageKey: String {
        switch self {
        case .standing: return "standing"
        case .sitting: return "sitting"
        case .shake: return "shake"
        case .rollover: return "rollover"
        case .playDead: return "playDead"
        }
    }

    var assetCandidates: [String] {
        return ["all"]
    }

    var frameRange: (start: Double, end: Double) {
        switch self {
        case .standing: return (0.0, 289.8)
        case .sitting: return (289.8, 577.8)
        case .shake: return (577.8, 725.0) 
        case .rollover: return (733.0, 925.0)
        // Trim playDead early to cut out the baked-in "lying dead" pause
        // so he bounces right back up.
        case .playDead: return (925.0, 1010.0)
        }
    }

    var barkCandidates: [String] {
        switch self {
        case .standing: return ["bark_1"]
        case .sitting: return ["bark_1"]
        case .shake: return ["bark_2"]
        case .rollover: return ["bark_3"]
        case .playDead: return ["bark_4"]
        }
    }

    var barkProfile: BarkSFXProfile {
        switch self {
        case .standing: return BarkSFXProfile(startOffset: 0.0, clipDuration: 0.45, secondaryDelay: nil, volume: 1.0)
        case .sitting: return BarkSFXProfile(startOffset: 0.05, clipDuration: 0.22, secondaryDelay: nil, volume: 0.95)
        case .shake: return BarkSFXProfile(startOffset: 0.1, clipDuration: 0.40, secondaryDelay: nil, volume: 1.0)
        case .rollover: return BarkSFXProfile(startOffset: 0.0, clipDuration: nil, secondaryDelay: nil, volume: 1.0)
        case .playDead: return BarkSFXProfile(startOffset: 0.0, clipDuration: 0.33, secondaryDelay: nil, volume: 0.98)
        }
    }

    var barkSequenceDelays: [Double] {
        switch self {
        case .standing: return [1.45, 3.5, 8.1]
        case .sitting: return [0.0, 2.1, 8.1]
        case .shake: return [0.0, 4.05]
        case .rollover: return []
        case .playDead: return [0.0, 6.1]
        }
    }

    var fallbackBarkDelay: Double {
        switch self {
        case .standing: return 0
        case .sitting: return 0.35
        case .shake: return 0.5
        case .rollover: return 0.6
        case .playDead: return 0.25
        }
    }
}

class DogVM: ObservableObject {
    @Published var selectedAction: DogAction = .standing
    @Published var loadedAnimationCount = 0
    @Published var statusMessage = "Ready"
    @Published var takeSnapshot = false
    @Published var capturedImage: UIImage? = nil
    
    // Preferences
    @Published var dogName: String = "Buddy"
    @Published var dogTint: UIColor = .white
    @Published var applyTint = false
    @Published var showPreferences = false

    func updateState(animator: Entity?, modelName: String?) {
        loadedAnimationCount = animator?.availableAnimations.count ?? 0
        if let modelName {
            statusMessage = "Loaded \(modelName) (clips: \(loadedAnimationCount))"
        } else {
            statusMessage = "Model load failed"
        }
        print(statusMessage)
    }
}

private extension Entity {
    func firstModelEntity() -> ModelEntity? {
        if let model = self as? ModelEntity { return model }
        for child in children {
            if let model = child.firstModelEntity() { return model }
        }
        return nil
    }

    func firstEntityWithAnimations() -> Entity? {
        if !availableAnimations.isEmpty { return self }
        for child in children {
            if let animated = child.firstEntityWithAnimations() { return animated }
        }
        return nil
    }
}

struct Btn: View {
    var txt: String  
    var act: () -> Void
    var body: some View {
        Button(action: act) {
            Text(txt).bold().foregroundColor(.white).padding().background(Color.red.opacity(0.7)).cornerRadius(8)
        }
    }
}

struct ARScreen: UIViewRepresentable {
    @ObservedObject var vm: DogVM

    class Coordinator: NSObject, ARSessionDelegate {
        weak var vm: DogVM?
        let anchor = AnchorEntity(plane: .horizontal)
        var currentDog: Entity?
        var currentDogModel: ModelEntity?
        var currentAnimator: Entity?
        var currentAction: DogAction?
        
        var nameTextEntity: ModelEntity?
        
        var animations: [DogAction: AnimationResource] = [:]
        
        var playbackCompletedSubscription: (any Cancellable)?
        var loadTask: Task<Void, Never>?
        
        var lastVisionProcessingTime = Date()
        var gestureConfidenceCount = 0
        var pendingAction: DogAction? = nil
        var indexTipHistory: [CGPoint] = []
        var hasInitializedAR = false

        func resetPlaybackCompletion() {
            playbackCompletedSubscription?.cancel()
            playbackCompletedSubscription = nil
        }
        
        @objc func handleTilt(_ sender: UIPanGestureRecognizer) {
            guard let model = currentDogModel else { return }
            let translation = sender.translation(in: sender.view)
            let pitchAngle = Float(translation.y) * 0.005 
            let rotationDelta = simd_quatf(angle: pitchAngle, axis: [1, 0, 0])
            model.transform.rotation = model.transform.rotation * rotationDelta
            sender.setTranslation(.zero, in: sender.view)
        }

        @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
            guard let dog = currentDog else { return }
            if sender.state == .began || sender.state == .changed {
                let currentScale = dog.scale.x
                let newScale = currentScale * Float(sender.scale)
                // Limit scale between a tiny 0.05 and a huge 1.0 limit
                let clampedScale = max(0.05, min(newScale, 1.0))
                dog.scale = .init(repeating: clampedScale)
                
                // Reset scale so the delta is relative on the next call
                sender.scale = 1.0
            }
        }
        
        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let view = sender.view as? ARView, let vm = vm else { return }
            let location = sender.location(in: view)
            
            if let result = view.hitTest(location, query: .nearest, mask: .all).first {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                
                // Set the dog action to shake playfully
                DispatchQueue.main.async {
                    vm.selectedAction = .shake
                }
                
                // Create a floating heart response
                let heartMesh = MeshResource.generateText("Good Boy!", extrusionDepth: 0.01, font: .systemFont(ofSize: 0.05), containerFrame: .zero, alignment: .center, lineBreakMode: .byCharWrapping)
                let heartMat = SimpleMaterial(color: .systemPink, isMetallic: false)
                let heart = ModelEntity(mesh: heartMesh, materials: [heartMat])
                
                heart.position = SIMD3<Float>(0, 0.4, 0)
                let cameraTransform = view.cameraTransform
                heart.look(at: cameraTransform.translation, from: heart.position, relativeTo: nil)
                
                result.entity.addChild(heart)
                
                var transform = heart.transform
                transform.translation.y += 0.2
                heart.move(to: transform, relativeTo: heart.parent, duration: 1.5, timingFunction: .easeOut)
                
                AudioManager.shared.playSFX(fromCandidates: ["bark_2"], delay: 0)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    heart.removeFromParent()
                }
            }
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let now = Date()
            
            if anchor.isAnchored && !hasInitializedAR {
                hasInitializedAR = true
                if let currentDog = currentDog {
                    let cameraPos = frame.camera.transform.columns.3
                    let dogPos = currentDog.position(relativeTo: nil)
                    let dx = cameraPos.x - dogPos.x
                    let dz = cameraPos.z - dogPos.z
                    let angle = atan2(dx, dz)
                    currentDog.transform.rotation = simd_quatf(angle: angle, axis: [0, 1, 0])
                }
                DispatchQueue.main.async { AudioManager.shared.startIfNeeded() }
            }
            
            guard now.timeIntervalSince(lastVisionProcessingTime) > 0.1 else { return }
            lastVisionProcessingTime = now
            
            guard vm?.selectedAction == .standing else {
                self.gestureConfidenceCount = 0
                self.pendingAction = nil
                self.indexTipHistory.removeAll()
                return
            }
            
            let pixelBuffer = frame.capturedImage
            
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectHumanHandPoseRequest { [weak self] req, err in
                    guard let self = self,
                          let obs = req.results?.first as? VNHumanHandPoseObservation else {
                        self?.indexTipHistory.removeAll()
                        self?.gestureConfidenceCount = 0
                        self?.pendingAction = nil
                        return
                    }
                    
                    if let idxTip = try? obs.recognizedPoint(.indexTip), idxTip.confidence > 0.4 {
                        self.indexTipHistory.append(idxTip.location)
                        if self.indexTipHistory.count > 20 { self.indexTipHistory.removeFirst() }
                    } else {
                        self.indexTipHistory.removeAll()
                    }
                    
                    let action = self.detectDogAction(from: obs)
                    
                    if action != nil && action == self.pendingAction {
                        self.gestureConfidenceCount += 1
                    } else {
                        self.pendingAction = action
                        self.gestureConfidenceCount = 0
                    }
                    
                    if self.gestureConfidenceCount >= 5, let confirmedAction = self.pendingAction {
                        DispatchQueue.main.async {
                            self.vm?.selectedAction = confirmedAction
                            self.gestureConfidenceCount = 0
                            self.indexTipHistory.removeAll()
                        }
                    }
                }
                request.maximumHandCount = 1
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
                try? handler.perform([request])
            }
        }
        
        private func detectDogAction(from obs: VNHumanHandPoseObservation) -> DogAction? {
            let thumbExt = isFingerExtended(.thumbTip, .thumbIP, obs: obs)
            let idxExt   = isFingerExtended(.indexTip, .indexPIP, obs: obs)
            let midExt   = isFingerExtended(.middleTip, .middlePIP, obs: obs)
            let rngExt   = isFingerExtended(.ringTip, .ringPIP, obs: obs)
            let litExt   = isFingerExtended(.littleTip, .littlePIP, obs: obs)
            
            let idxCls = isFingerClosed(.indexTip, .indexPIP, obs: obs)
            let midCls = isFingerClosed(.middleTip, .middlePIP, obs: obs)
            let rngCls = isFingerClosed(.ringTip, .ringPIP, obs: obs)
            let litCls = isFingerClosed(.littleTip, .littlePIP, obs: obs)
            
            // 1. Open Palm 🖐 -> Rollover
            if thumbExt && idxExt && midExt && rngExt && litExt { return .rollover }
            
            // 2. Fist ✊ -> Shake
            if idxCls && midCls && rngCls && litCls { return .shake }
            
            // 3. Peace Sign ✌️ -> Sitting (Index/Middle out, Ring/Little closed)
            if idxExt && midExt && rngCls && litCls { return .sitting }
            
            // 4. Pointing / Gun 👈 -> Play Dead (Index out, Middle/Ring/Little closed)
            if idxExt && midCls && rngCls && litCls { return .playDead }
            
            return nil 
        }
        
        private func isFingerExtended(_ tip: VNHumanHandPoseObservation.JointName, _ pip: VNHumanHandPoseObservation.JointName, obs: VNHumanHandPoseObservation) -> Bool {
            guard let pTip = try? obs.recognizedPoint(tip),
                  let pPip = try? obs.recognizedPoint(pip),
                  let pWrist = try? obs.recognizedPoint(.wrist) else { return false }
            
            guard pTip.confidence > 0.3 && pPip.confidence > 0.3 && pWrist.confidence > 0.3 else { return false }
            
            let dTip = hypot(pTip.location.x - pWrist.location.x, pTip.location.y - pWrist.location.y)
            let dPip = hypot(pPip.location.x - pWrist.location.x, pPip.location.y - pWrist.location.y)
            
            return dTip > (dPip * 1.1)
        }
        
        private func isFingerClosed(_ tip: VNHumanHandPoseObservation.JointName, _ pip: VNHumanHandPoseObservation.JointName, obs: VNHumanHandPoseObservation) -> Bool {
            guard let pTip = try? obs.recognizedPoint(tip),
                  let pPip = try? obs.recognizedPoint(pip),
                  let pWrist = try? obs.recognizedPoint(.wrist) else { return false }
            
            guard pTip.confidence > 0.3 && pPip.confidence > 0.3 && pWrist.confidence > 0.3 else { return false }
            
            let dTip = hypot(pTip.location.x - pWrist.location.x, pTip.location.y - pWrist.location.y)
            let dPip = hypot(pPip.location.x - pWrist.location.x, pPip.location.y - pWrist.location.y)
            
            return dTip < (dPip * 1.05) 
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.vm = vm
        return coordinator
    }

    func makeUIView(context: Context) -> ARView {
        let v = ARView(frame: .zero)
        let cfg = ARWorldTrackingConfiguration()
        cfg.planeDetection = [.horizontal]
        cfg.environmentTexturing = .automatic
        
        // Enable People Occlusion (if supported by the device)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            cfg.frameSemantics.insert(.personSegmentationWithDepth)
        }
        
        // Fix Collision: Enable Object Occlusion (LiDAR) for better depth sorting
        // Switching to .smoothedSceneDepth reduces the "laggy/jagged" glitching on fast-moving objects like hands
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            cfg.frameSemantics.insert(.smoothedSceneDepth)
            v.environment.sceneUnderstanding.options.insert(.occlusion)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            cfg.frameSemantics.insert(.sceneDepth)
            v.environment.sceneUnderstanding.options.insert(.occlusion)
        }
        
        // Fix Lighting: Boost brightness slightly and create extra directional light
        v.environment.lighting.intensityExponent = 1.3
        
        // Let's attach our fill light to the camera so it always illuminates the front of the dog perfectly!
        let lightEntity = Entity()
        let light = DirectionalLightComponent(color: .white, intensity: 1500, isRealWorldProxy: false)
        lightEntity.components.set(light)
        
        let cameraAnchor = AnchorEntity(.camera)
        cameraAnchor.addChild(lightEntity)
        v.scene.addAnchor(cameraAnchor)
        
        // Removed old fixed-position light
        v.session.delegate = context.coordinator
        v.session.run(cfg)
        v.scene.addAnchor(context.coordinator.anchor)
        
        let tiltGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTilt(_:)))
        tiltGesture.minimumNumberOfTouches = 2
        tiltGesture.maximumNumberOfTouches = 2
        v.addGestureRecognizer(tiltGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        v.addGestureRecognizer(pinchGesture)
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        v.addGestureRecognizer(tapGesture)
        
        loadDog(for: vm.selectedAction, in: v, coordinator: context.coordinator)
        return v
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        if vm.takeSnapshot {
            DispatchQueue.main.async { vm.takeSnapshot = false }
            uiView.snapshot(saveToHDR: false) { image in
                guard let image = image else { return }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                DispatchQueue.main.async {
                    context.coordinator.vm?.statusMessage = "Saved to Gallery!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if context.coordinator.vm?.statusMessage == "Saved to Gallery!" {
                            context.coordinator.vm?.statusMessage = "Ready"
                        }
                    }
                }
            }
        }

        let coordinator = context.coordinator
        
        // Dynamic properties: Name tag & Texture Tint
        if let dogModel = coordinator.currentDogModel {
            if coordinator.nameTextEntity == nil && !vm.dogName.isEmpty {
                let textMesh = MeshResource.generateText(vm.dogName, extrusionDepth: 0.01, font: .systemFont(ofSize: 0.2), containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
                let textMaterial = SimpleMaterial(color: .white, isMetallic: false)
                let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
                
                // Position above the dog
                textEntity.position = SIMD3<Float>(-0.3, 1.2, 0)
                dogModel.addChild(textEntity)
                coordinator.nameTextEntity = textEntity
            } else if let textEntity = coordinator.nameTextEntity {
                textEntity.model?.mesh = MeshResource.generateText(vm.dogName, extrusionDepth: 0.01, font: .systemFont(ofSize: 0.2), containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
            }
            
            if vm.applyTint {
                DispatchQueue.main.async { vm.applyTint = false }
                if var modelComponent = dogModel.model {
                    for i in 0..<modelComponent.materials.count {
                        if var pbr = modelComponent.materials[i] as? PhysicallyBasedMaterial {
                            pbr.baseColor.tint = vm.dogTint
                            modelComponent.materials[i] = pbr
                        } else if var simple = modelComponent.materials[i] as? SimpleMaterial {
                            simple.color.tint = vm.dogTint
                            modelComponent.materials[i] = simple
                        }
                    }
                    dogModel.model = modelComponent
                }
            }
        }

        guard coordinator.currentAction != vm.selectedAction else { return }
        loadDog(for: vm.selectedAction, in: uiView, coordinator: coordinator)
    }

    private func loadDog(for action: DogAction, in arView: ARView, coordinator: Coordinator) {
        coordinator.resetPlaybackCompletion()
        AudioManager.shared.stopSFX()

        if let animator = coordinator.currentAnimator,
           let slicedAnim = coordinator.animations[action] {
            
            let oldAction = coordinator.currentAction
            coordinator.currentAction = action
            let animToPlay = action == .standing ? slicedAnim.repeat() : slicedAnim
            
            var transition: Double = 0.5
            if action == .playDead {
                transition = 0.9 
            } else if (oldAction == .playDead || oldAction == .rollover) && action == .sitting {
                // The animation is actively pre-empted now before it finishes, 
                // so a standard 1.2s blend will smoothly float the dog up naturally.
                transition = 1.2
            } else if oldAction == .sitting && action == .standing {
                // He is sitting. Blend to standing smoothly.
                transition = 0.8
            } else if action == .rollover {
                transition = 0.7
            }
            
            let playbackController = animator.playAnimation(animToPlay, transitionDuration: transition, startsPaused: false)
            playBarkSequence(for: action, in: arView, coordinator: coordinator, playbackController: playbackController)
            return
        }

        let oldAction = coordinator.currentAction
        coordinator.currentAction = action 
        coordinator.loadTask?.cancel()

        coordinator.loadTask = Task { @MainActor in
            guard let loaded = await loadEntityAsync(for: action) else {
                if !Task.isCancelled { vm.updateState(animator: nil, modelName: nil) }
                return
            }
            guard !Task.isCancelled else { return }

            let dogModel = loaded.firstModelEntity()
            let animator = loaded.firstEntityWithAnimations()

            loaded.scale = .init(repeating: 0.2)
            dogModel?.generateCollisionShapes(recursive: true)
            dogModel?.components.set(InputTargetComponent())
            
            let pitchCorrection = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            dogModel?.transform.rotation = pitchCorrection
            
            coordinator.anchor.addChild(loaded)
            coordinator.currentDog = loaded
            coordinator.currentDogModel = dogModel
            coordinator.currentAnimator = animator

            if let dogModel { arView.installGestures(.all, for: dogModel) }

            if let fullAnim = animator?.availableAnimations.first {
                let fps = 24.0 
                for actionCase in DogAction.allCases {
                    let range = actionCase.frameRange
                    var view = AnimationView(source: fullAnim.definition)
                    view.name = actionCase.title
                    view.repeatMode = .none 
                    view.trimStart = range.start / fps
                    view.trimEnd = range.end / fps
                    if let sliced = try? AnimationResource.generate(with: view) {
                        coordinator.animations[actionCase] = sliced
                    }
                }
            }

            var playbackController: AnimationPlaybackController?
            if let slicedAnim = coordinator.animations[action] {
                let animToPlay = action == .standing ? slicedAnim.repeat() : slicedAnim
                var transition: Double = 0.5
                if action == .playDead {
                    transition = 0.9
                } else if (oldAction == .playDead || oldAction == .rollover) && action == .sitting {
                    transition = 2.0
                } else if oldAction == .sitting && action == .standing {
                    transition = 0.8
                } else if action == .rollover {
                    transition = 0.7
                }
                playbackController = animator?.playAnimation(animToPlay, transitionDuration: transition, startsPaused: false)
            }

            playBarkSequence(for: action, in: arView, coordinator: coordinator, playbackController: playbackController)
            vm.updateState(animator: animator, modelName: "all.usdz")
        }
    }

    private func playBarkSequence(
        for action: DogAction,
        in arView: ARView,
        coordinator: Coordinator,
        playbackController: AnimationPlaybackController?
    ) {
        guard !action.barkCandidates.isEmpty else { return }

        let profile = action.barkProfile
        let delays = action.barkSequenceDelays
        
        if !delays.isEmpty {
            AudioManager.shared.playSFXSequence(fromCandidates: action.barkCandidates, delays: delays, profile: profile)
        } else {
            AudioManager.shared.playSFX(fromCandidates: action.barkCandidates, delay: action.fallbackBarkDelay, profile: profile)
        }

        if action == .standing {
            coordinator.playbackCompletedSubscription = arView.scene.subscribe(to: AnimationEvents.PlaybackCompleted.self) { _ in
                guard vm.selectedAction == .standing else {
                    coordinator.resetPlaybackCompletion()
                    return
                }
                if !delays.isEmpty {
                    AudioManager.shared.playSFXSequence(fromCandidates: action.barkCandidates, delays: delays, profile: profile)
                } else {
                    AudioManager.shared.playSFX(fromCandidates: action.barkCandidates, delay: action.fallbackBarkDelay, profile: profile)
                }
            }
            return
        }

        guard playbackController != nil else { return }

        // Pre-empt lying down animations just BEFORE they finish so RealityKit doesn't drop the active pose
        // If they finish, RealityKit resets to T-Pose natively before the transition kicks in, causing a snap.
        if action == .playDead || action == .rollover {
            let fps = 24.0
            let duration = (action.frameRange.end - action.frameRange.start) / fps
            // Trigger the sit 0.4s before the animation ends so the active lay-down pose crossfades smoothly
            let preEmptTime = max(0.1, duration - 0.4)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + preEmptTime) {
                if self.vm.selectedAction == action {
                    self.vm.selectedAction = .sitting
                    
                    // Stand up after sitting for a few seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if self.vm.selectedAction == .sitting {
                            self.vm.selectedAction = .standing
                        }
                    }
                }
            }
            return
        }

        coordinator.playbackCompletedSubscription = arView.scene.subscribe(to: AnimationEvents.PlaybackCompleted.self) { _ in
            var returnToStandingDelay: Double = 0.05
            if action == .sitting || action == .shake {
                AudioManager.shared.playSFX(fromCandidates: action.barkCandidates, delay: 0, profile: profile, interruptExisting: false)
                returnToStandingDelay = 0.5
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + returnToStandingDelay) {
                if vm.selectedAction == action {
                    vm.selectedAction = .standing
                }
            }
            coordinator.resetPlaybackCompletion()
        }
    }

    private func loadEntityAsync(for action: DogAction) async -> Entity? {
        for file in action.assetCandidates {
            if let entity = try? await Entity(named: file) { return entity }
        }
        return nil
    }
}
