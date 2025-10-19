import ARKit
import Foundation

class FlutterArkitView: NSObject, FlutterPlatformView, ARSCNViewDelegate {
    let sceneView: ARSCNView
    let channel: FlutterMethodChannel
    var forceTapOnCenter: Bool = false
    var configuration: ARConfiguration? = nil

    init(withFrame frame: CGRect, viewIdentifier viewId: Int64, messenger msg: FlutterBinaryMessenger) {
        sceneView = ARSCNView(frame: frame)
        channel = FlutterMethodChannel(name: "arkit_\(viewId)", binaryMessenger: msg)
        super.init()
        print("FlutterArkitView initialized with viewId: \(viewId)")
        sceneView.delegate = self
        channel.setMethodCallHandler(onMethodCalled)
    }

    func view() -> UIView { return sceneView }

    func configureSession(_ arguments: [String: Any]?) {
        let config = ARWorldTrackingConfiguration()
        if #available(iOS 14.0, *) {
            config.frameSemantics.insert(.sceneDepth)
        }
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        configuration = config
    }

    @available(iOS 14.0, *)
    func snapshotWithDepthData(_ result: @escaping FlutterResult) {
        guard let frame = sceneView.session.currentFrame else {
            result(FlutterError(code: "NO_FRAME", message: "No current frame", details: nil))
            return
        }
        guard let depthData = frame.sceneDepth else {
            result(FlutterError(code: "NO_DEPTH_DATA", message: "No depth data available", details: nil))
            return
        }
        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        // Конвертация depthMap в массив Float
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthMap), to: UnsafeMutablePointer<Float>.self)
        let depthArray = Array(UnsafeBufferPointer(start: floatBuffer, count: depthWidth * depthHeight))
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)

        // Конвертация confidenceMap в массив UInt8
        var confidenceArray: [UInt8] = []
        if let confidence = confidenceMap {
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
            let confidenceBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(confidence), to: UnsafeMutablePointer<UInt8>.self)
            confidenceArray = Array(UnsafeBufferPointer(start: confidenceBuffer, count: depthWidth * depthHeight))
            CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
        }

        // Получение transform
        let transform = frame.camera.transform
        let columns = [transform.columns.0, transform.columns.1, transform.columns.2, transform.columns.3]
        let transformArray = columns.flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }

        result([
            "depthMap": depthArray,
            "confidenceMap": confidenceArray,
            "depthWidth": depthWidth,
            "depthHeight": depthHeight,
            "transform": transformArray
        ])
    }

    func onMethodCalled(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        print("onMethodCalled: \(call.method), arguments: \(String(describing: call.arguments))")
        let arguments = call.arguments as? [String: Any]
        if configuration == nil && call.method != "init" {
            logPluginError("plugin is not initialized properly", toChannel: channel)
            result(nil)
            return
        }
        switch call.method {
        case "init", "initCustomConfiguration":
            print("Configuring session for init")
            configureSession(arguments)
            print("Invoking onInitialized")
            channel.invokeMethod("onInitialized", arguments: nil)
            result(nil)
        case "addARKitNode":
            onAddNode(arguments!)
            result(nil)
        case "onUpdateNode":
            onUpdateNode(arguments!)
            result(nil)
        case "removeARKitNode":
            onRemoveNode(arguments!)
            result(nil)
        case "removeARKitAnchor":
            onRemoveAnchor(arguments!)
            result(nil)
        case "addCoachingOverlay":
            if #available(iOS 13.0, *) {
                addCoachingOverlay(arguments!)
            }
            result(nil)
        case "removeCoachingOverlay":
            if #available(iOS 13.0, *) {
                removeCoachingOverlay()
            }
            result(nil)
        case "getNodeBoundingBox":
            onGetNodeBoundingBox(arguments!, result)
        case "transformationChanged":
            onTransformChanged(arguments!)
            result(nil)
        case "isHiddenChanged":
            onIsHiddenChanged(arguments!)
            result(nil)
        case "updateSingleProperty":
            onUpdateSingleProperty(arguments!)
            result(nil)
        case "updateMaterials":
            onUpdateMaterials(arguments!)
            result(nil)
        case "performHitTest":
            onPerformHitTest(arguments!, result)
        case "updateFaceGeometry":
            onUpdateFaceGeometry(arguments!)
            result(nil)
        case "getLightEstimate":
            onGetLightEstimate(result)
            result(nil)
        case "projectPoint":
            onProjectPoint(arguments!, result)
        case "cameraProjectionMatrix":
            onCameraProjectionMatrix(result)
        case "pointOfViewTransform":
            onPointOfViewTransform(result)
        case "playAnimation":
            onPlayAnimation(arguments!)
            result(nil)
        case "stopAnimation":
            onStopAnimation(arguments!)
            result(nil)
        case "dispose":
            onDispose(result)
            result(nil)
        case "cameraEulerAngles":
            onCameraEulerAngles(result)
            result(nil)
        case "cameraIntrinsics":
            onCameraIntrinsics(result)
        case "captureHighResImage":
            print("Capturing high resolution image")
            guard let currentFrame = sceneView.session.currentFrame else {
                print("No current frame available")
                result(nil)
                return
            }
            let image = currentFrame.capturedImage
            guard let imageData = CIImage(cvPixelBuffer: image).jpegRepresentation() else {
                print("Failed to convert image to JPEG")
                result(nil)
                return
            }
            print("High res image captured, size: \(imageData.count) bytes")
            result(imageData)
        case "cameraImageResolution":
            print("Getting camera image resolution")
            guard let currentFrame = sceneView.session.currentFrame else {
                print("No current frame available")
                result(nil)
                return
            }
            let pixelBuffer = currentFrame.capturedImage
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            print("Camera image resolution: \(width)x\(height)")
            result([Double(width), Double(height)])
        case "snapshot":
            onGetSnapshot(result)
        case "capturedImage":
            onCameraCapturedImage(result)
        case "snapshotWithDepthData":
            if #available(iOS 14.0, *) {
                snapshotWithDepthData(result)
            } else {
                // Fallback on earlier versions
            }
        case "cameraPosition":
            onGetCameraPosition(result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func sendToFlutter(_ method: String, arguments: Any?) {
        DispatchQueue.main.async {
            self.channel.invokeMethod(method, arguments: arguments)
        }
    }

    func onDispose(_ result: FlutterResult) {
        sceneView.session.pause()
        channel.setMethodCallHandler(nil)
        result(nil)
    }
//
//    // Заглушки для методов, которые не предоставлены в твоём коде
//    func onAddNode(_ arguments: [String: Any]) {}
//    func onUpdateNode(_ arguments: [String: Any]) {}
//    func onRemoveNode(_ arguments: [String: Any]) {}
//    func onRemoveAnchor(_ arguments: [String: Any]) {}
//    func addCoachingOverlay(_ arguments: [String: Any]) {}
//    func removeCoachingOverlay() {}
//    func onGetNodeBoundingBox(_ arguments: [String: Any], _ result: FlutterResult) {}
//    func onTransformChanged(_ arguments: [String: Any]) {}
//    func onIsHiddenChanged(_ arguments: [String: Any]) {}
//    func onUpdateSingleProperty(_ arguments: [String: Any]) {}
//    func onUpdateMaterials(_ arguments: [String: Any]) {}
//    func onPerformHitTest(_ arguments: [String: Any], _ result: FlutterResult) {}
//    func onUpdateFaceGeometry(_ arguments: [String: Any]) {}
//    func onGetLightEstimate(_ result: FlutterResult) {}
//    func onProjectPoint(_ arguments: [String: Any], _ result: FlutterResult) {}
//    func onCameraProjectionMatrix(_ result: FlutterResult) {}
//    func onPointOfViewTransform(_ result: FlutterResult) {}
//    func onPlayAnimation(_ arguments: [String: Any]) {}
//    func onStopAnimation(_ arguments: [String: Any]) {}
//    func onCameraEulerAngles(_ result: FlutterResult) {}
//    func onCameraIntrinsics(_ result: FlutterResult) {}
//    func onCameraImageResolution(_ result: FlutterResult) {}
//    func onGetSnapshot(_ result: FlutterResult) {}
//    func onCameraCapturedImage(_ result: FlutterResult) {}
//    func onGetCameraPosition(_ result: FlutterResult) {}
}

extension CIImage {
    func jpegRepresentation() -> Data? {
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(self, from: self.extent) else {
            return nil
        }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 1.0)
    }
}