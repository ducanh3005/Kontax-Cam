//
//  CameraEngine.swift
//  Kontax Cam
//
//  Created by Kevin Laminto on 28/6/20.
//  Copyright © 2020 Kevin Laminto. All rights reserved.
//

import AVFoundation
import CoreMotion
import UIKit
import MetalKit

class CameraEngine: NSObject {
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    enum CameraEngineError: String, Error {
        case noInput = "No input detected"
        case setupExtraLensInput = "Unable to setup extra lens input"
    }
    
    private var setupResult: SessionSetupResult = .success
    
    private var captureSession = AVCaptureSession()
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInDualCamera, .builtInWideAngleCamera],
        mediaType: .video,
        position: .unspecified)
    private var backCamera: AVCaptureDevice?
    private var frontCamera: AVCaptureDevice?
    var currentCamera: AVCaptureDevice?
    
    private let dataOutputQueue = DispatchQueue(label: "VideoDataQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private let photoDataOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    private var captureImageCompletion: ((UIImage?) -> Void)?
    
    private var deviceOrientation: UIDeviceOrientation = .portrait
    private var cameraIsObservingDeviceOrientation = false
    
    private var coreMotionManager: CMMotionManager!
    
    private var lastFocusCircle: CAShapeLayer?
    private var lastFocusPoint: CGPoint?
    
    private var focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
    private var exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
    
    private var captureView: UIView = {
        let v = UIView()
        v.layer.opacity = 0
        v.backgroundColor = .black
        return v
    }()
    
    var flashMode: AVCaptureDevice.FlashMode = .off
    var isCapturing = false {
        didSet {
            showCaptureAnimation()
        }
    }
    
    var showFilter = false
    var previewView: PreviewMetalView?
    let filter = LUTRender()
    
    var supportedExtraLens = [AVCaptureDevice?]()
    
    private let minimumZoom: CGFloat = 1.0
    private let maximumZoom: CGFloat = 3.0
    private var lastZoomFactor: CGFloat = 1.0
    
    override init() {
        super.init()
        checkPermission()
        setupCaptureSession()
        setupExtraLens()
    }
    
    // MARK: - Public methods
    /// Add the camera preview layer to the given view
    /// - Parameter view: The view that will receive the camera preview layer
    func addPreviewLayer(toView view: UIView) {
        self.previewView = view as? PreviewMetalView
        setPreviewViewOrientation()
        
        startRunningCaptureSession()
        attachFocus(view)
        
        setupZoom(toView: view)
    }
    
    /// Capture the image
    func captureImage(completion: @escaping (UIImage?) -> Void) {
        if currentCamera == nil {
            print("❗️Unable to capture image")
            return
        }
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashMode
        photoDataOutput.capturePhoto(with: settings, delegate: self)
        self.captureImageCompletion = completion
    }
    
    /// Resume the capture session
    func startCaptureSession() {
        captureSession.startRunning()
        _startFollowingDeviceOrientation()
    }
    
    /// Stop the capture session, for performance
    func stopCaptureSession() {
        captureSession.stopRunning()
        _stopFollowingDeviceOrientation()
    }
    
    /// Switch the camera between front and back
    func switchCamera() {
        guard let input = captureSession.inputs.first else {
            print("❗️No input detected")
            return
        }
        captureSession.removeInput(input)
        do {
            let newCamera = currentCamera?.position == AVCaptureDevice.Position.back ? frontCamera! : backCamera!
            
            let captureDeviceInput = try AVCaptureDeviceInput(device: newCamera)
            captureSession.addInput(captureDeviceInput)
            currentCamera = newCamera
            
            setPreviewViewOrientation()
            lastZoomFactor = 1.0
        } catch {
            print(error)
        }
    }
    
    /// Render new filter if needed
    func renderNewFilter(withFilterName filterName: FilterName) {
        dataOutputQueue.async {
            self.filter.reset()
            self.filter._renderNewFilter(filterName)
        }
    }
    
    func updateLens(completion: @escaping (Result<Bool, CameraEngineError>) -> Swift.Void) {
        guard let input = captureSession.inputs.first else {
            print("❗️No input detected")
            completion(.failure(.noInput))
            return
        }
        
        let newCamera = getNextExtraLens()!
        
        captureSession.removeInput(input)
        do {
            let captureDeviceInput = try AVCaptureDeviceInput(device: newCamera)
            captureSession.addInput(captureDeviceInput)
            currentCamera = newCamera
            
            setPreviewViewOrientation()
            lastZoomFactor = 1.0
            completion(.success(true))
        } catch {
            completion(.failure(.setupExtraLensInput))
        }
        
    }
    
    // MARK: - Private methods
    /// Setup zoom control to allow pinch to zoom
    private func setupZoom(toView view: UIView) {
        let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinch))
        view.addGestureRecognizer(pinchRecognizer)
    }
    
    @objc private func pinch(_ pinch: UIPinchGestureRecognizer) {
        guard let device = currentCamera else { return }
        
        // Return zoom value between the minimum and maximum zoom values
        func minMaxZoom(_ factor: CGFloat) -> CGFloat {
            return min(min(max(factor, minimumZoom), maximumZoom), device.activeFormat.videoMaxZoomFactor)
        }
        
        func update(scale factor: CGFloat) {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.videoZoomFactor = factor
            } catch {
                print("\(error.localizedDescription)")
            }
        }
        
        let newScaleFactor = minMaxZoom(pinch.scale * lastZoomFactor)
        
        switch pinch.state {
        case .changed: update(scale: newScaleFactor)
        case .ended:
            lastZoomFactor = minMaxZoom(newScaleFactor)
            update(scale: lastZoomFactor)
        default: break
        }
    }
    
    /// Setup extra lens
    private func setupExtraLens() {
        // If triple camera, add telephoto and ultrawide settings.
        if AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) != nil {
            let extraLens = [
                AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back),
                AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            ]
            
            supportedExtraLens = extraLens
            
        } else if AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) != nil {
            let extraLens = [
                AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
            ]
            
            supportedExtraLens = extraLens
            
        } else if AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) != nil {
            let extraLens = [
                AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            ]
            
            supportedExtraLens = extraLens
            
        } else {
            supportedExtraLens = [nil]
        }
    }
    
    /// Get the next extra lens that should be presented
    private func getNextExtraLens() -> AVCaptureDevice? {
        guard let input = captureSession.inputs[0] as? AVCaptureDeviceInput else { return backCamera }
        
        if var currentIndex = supportedExtraLens.firstIndex(of: input.device) {
            currentIndex += 1 // get the next value
            return currentIndex >= supportedExtraLens.count ? backCamera : supportedExtraLens[currentIndex]
            
        } else {
            return supportedExtraLens.first ?? backCamera
        }
    }
    
    /// Setup previewView orientation
    private func setPreviewViewOrientation() {
        let interfaceOrientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation
        if let unwrappedVideoDataOutputConnection = self.videoDataOutput.connection(with: .video) {
            let videoDevicePosition = currentCamera?.position
            let rotation = PreviewMetalView.Rotation(with: interfaceOrientation!,
                                                     videoOrientation: unwrappedVideoDataOutputConnection.videoOrientation,
                                                     cameraPosition: videoDevicePosition!)
            self.previewView?.mirroring = videoDevicePosition == .front
            if let rotation = rotation {
                self.previewView!.rotation = rotation
            }
        }
    }
    
    /// Check for user permission to use the camera
    private func checkPermission() {
        // Check video authorization status, video access is required
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant video access
             Suspend the SessionQueue to delay session setup until the access request has completed
             */
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
            })
            
        default:
            // The user has previously denied access
            setupResult = .notAuthorized
        }
    }
    
    /// Setup the capture session for the custom camera.
    ///
    /// First, set the device to be back camera by default, And then we create the input and output stream.
    /// We added video input and output for the live rendering of filters, whilst photo is for exporting only.
    private func setupCaptureSession() {
        captureSession.sessionPreset = .photo
        
        // Setup device
        let devices = videoDeviceDiscoverySession.devices
        for device in devices {
            if device.position == .back {
                backCamera = device
            } else if device.position == .front {
                frontCamera = device
            }
        }
        
        currentCamera = backCamera
        guard let currentCamera = currentCamera else {
            print("❗️No camera found")
            return
        }
        // Setup Input and Output
        
        do {
            let captureDeviceInput = try AVCaptureDeviceInput(device: currentCamera)
            
            captureSession.beginConfiguration()
            
            // Setup video input
            if captureSession.canAddInput(captureDeviceInput) {
                captureSession.addInput(captureDeviceInput)
            }
            
            // Setup video data output
            if captureSession.canAddOutput(videoDataOutput) {
                videoDataOutput.alwaysDiscardsLateVideoFrames = true
                captureSession.addOutput(videoDataOutput)
                videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
            }
            
            // Setup photo data output
            if captureSession.canAddOutput(photoDataOutput) {
                captureSession.addOutput(photoDataOutput)
                
                photoDataOutput.isHighResolutionCaptureEnabled = true
                photoDataOutput.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])], completionHandler: nil)
            }
        } catch {
            print(error)
        }
        captureSession.commitConfiguration()
    }
    
    /// Tells the class to start the session
    private func startRunningCaptureSession() {
        captureSession.startRunning()
    }
    
    /// Fix the captured image to properly follows the device
    private func fixOrientation(withImage image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        var isMirrored = !(currentCamera!.position == AVCaptureDevice.Position.back)
        let orientation = image.imageOrientation
        if orientation == .rightMirrored
            || orientation == .leftMirrored
            || orientation == .upMirrored
            || orientation == .downMirrored {
            isMirrored = true
        }
        
        let newOrientation = _imageOrientation(forDeviceOrientation: deviceOrientation, isMirrored: isMirrored)
        
        if image.imageOrientation != newOrientation {
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: newOrientation)
        }
        
        return image
    }
    
    private func _imageOrientation(forDeviceOrientation deviceOrientation: UIDeviceOrientation, isMirrored: Bool) -> UIImage.Orientation {
        
        switch deviceOrientation {
        case .landscapeLeft:
            return isMirrored ? .upMirrored : .up
        case .landscapeRight:
            return isMirrored ? .downMirrored : .down
        default:
            break
        }
        
        return isMirrored ? .leftMirrored : .right
    }
    
    private func _startFollowingDeviceOrientation() {
        if !cameraIsObservingDeviceOrientation {
            coreMotionManager = CMMotionManager()
            coreMotionManager.deviceMotionUpdateInterval = 1 / 30.0
            if coreMotionManager.isDeviceMotionAvailable {
                coreMotionManager.startDeviceMotionUpdates(to: OperationQueue()) { motion, _ in
                    guard let motion = motion else { return }
                    let x = motion.gravity.x
                    let y = motion.gravity.y
                    
                    if fabs(y) >= fabs(x) {
                        self.deviceOrientation = y >= 0 ? .portraitUpsideDown : .portrait
                    } else {
                        self.deviceOrientation = x >= 0 ? .landscapeRight : .landscapeLeft
                    }
                }
                cameraIsObservingDeviceOrientation = true
            } else {
                cameraIsObservingDeviceOrientation = false
            }
        }
    }
    
    private func _stopFollowingDeviceOrientation() {
        if cameraIsObservingDeviceOrientation {
            coreMotionManager.stopDeviceMotionUpdates()
            cameraIsObservingDeviceOrientation = false
        }
    }
    
    /// Attach focus gesture to the view.
    private func attachFocus(_ view: UIView) {
        // Add tap to focus gesture
        let focusTapGesture = UITapGestureRecognizer(target: self, action: #selector(onFocusTapped))
        view.addGestureRecognizer(focusTapGesture)
    }
    
    /// Runs when user tap to focus
    @objc private func onFocusTapped(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: previewView)
        guard let texturePoint = previewView!.texturePointForView(point: location) else { return }
        
        let textureRect = CGRect(origin: texturePoint, size: .zero)
        let deviceRect = videoDataOutput.metadataOutputRectConverted(fromOutputRect: textureRect)
        
        // Show the focus ring
        if let view = recognizer.view {
            let pointInPreviewLayer = view.layer.convert(recognizer.location(in: view), to: previewView!.layer)
            showFocusCircle(atPoint: pointInPreviewLayer, inLayer: previewView!.layer)
        }
        
        // Do the actual focus
        focus(with: .autoFocus, exposureMode: .continuousAutoExposure, at: deviceRect.origin, monitorSubjectAreaChange: true)
    }
    
    /// Focus on the given point
    private func focus(with focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, at devicePoint: CGPoint, monitorSubjectAreaChange: Bool) {
        
        let videoDevice = currentCamera!
        
        do {
            try videoDevice.lockForConfiguration()
            if videoDevice.isFocusPointOfInterestSupported && videoDevice.isFocusModeSupported(focusMode) {
                videoDevice.focusPointOfInterest = devicePoint
                videoDevice.focusMode = focusMode
            }
            
            if videoDevice.isExposurePointOfInterestSupported && videoDevice.isExposureModeSupported(exposureMode) {
                videoDevice.exposurePointOfInterest = devicePoint
                videoDevice.exposureMode = exposureMode
            }
            
            videoDevice.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
            videoDevice.unlockForConfiguration()
        } catch {
            print("Could not lock device for configuration: \(error)")
        }
    }
    
    /// Show the focus circle and its animation
    private func showFocusCircle(atPoint point: CGPoint, inLayer layer: CALayer) {
        // Remove previous focus circle
        if let lastFocusCircle = lastFocusCircle {
            lastFocusCircle.removeFromSuperlayer()
            self.lastFocusCircle = nil
        }
        
        // Draw the focus circle
        let shapeLayer = CAShapeLayer()
        let center = point
        let circulPath = UIBezierPath(arcCenter: center, radius: 30, startAngle: 0, endAngle: 2.0 * CGFloat.pi, clockwise: true)
        
        shapeLayer.path = circulPath.cgPath
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = UIColor(red: 1, green: 0.83, blue: 0, alpha: 0.95).cgColor
        shapeLayer.lineWidth = 1.0
        
        layer.addSublayer(shapeLayer)
        lastFocusCircle = shapeLayer
        lastFocusPoint = point
        
        // Set fadeout animation
        CATransaction.begin()
        
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut))
        
        CATransaction.setCompletionBlock {
            if shapeLayer.superlayer != nil {
                shapeLayer.removeFromSuperlayer()
                self.lastFocusCircle = nil
            }
        }
        
        let disappearOpacityAnimation = CABasicAnimation(keyPath: "opacity")
        disappearOpacityAnimation.fromValue = 1.0
        disappearOpacityAnimation.toValue = 0.0
        disappearOpacityAnimation.beginTime = CACurrentMediaTime() + 0.8
        disappearOpacityAnimation.fillMode = CAMediaTimingFillMode.forwards
        disappearOpacityAnimation.isRemovedOnCompletion = false
        shapeLayer.add(disappearOpacityAnimation, forKey: "opacity")
        
        CATransaction.commit()
    }
    
    /// Show the capture animation
    private func showCaptureAnimation() {
        let duration: Double = 0.0625
        if previewView != nil {
            if isCapturing {
                captureView.frame = previewView!.bounds
                previewView!.addSubview(captureView)
                UIView.animate(withDuration: duration) {
                    self.captureView.layer.opacity = 1
                }
            } else {
                UIView.animate(withDuration: duration, animations: {
                    self.captureView.layer.opacity = 0
                }) { (_) in
                    self.captureView.removeFromSuperview()
                }
            }
            
        }
    }
    
}

extension CameraEngine: AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        var capturedImage: UIImage?
        
        if let data = photo.fileDataRepresentation() {
            if let image = UIImage(data: data) {
                capturedImage = fixOrientation(withImage: image)
            }
        }
        captureImageCompletion!(capturedImage)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        renderVideo(sampleBuffer: sampleBuffer)
    }
    
    /// Render the raw buffer into a filtered buffer
    private func renderVideo(sampleBuffer: CMSampleBuffer) {
        guard
            let videoPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        
        var finalVideoPixelBuffer = videoPixelBuffer
        
        if showFilter {
            if !filter.isPrepared {
                filter.prepare(with: formatDescription, outputRetainedBufferCountHint: 3)
            }
            guard let filteredBuffer = filter.render(pixelBuffer: finalVideoPixelBuffer) else { return }
            
            finalVideoPixelBuffer = filteredBuffer
        }
        
        previewView?.pixelBuffer = finalVideoPixelBuffer
    }
}
