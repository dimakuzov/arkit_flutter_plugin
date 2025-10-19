import ARKit
import Flutter
import UIKit

public class SwiftArkitPlugin: NSObject, FlutterPlugin {
    public static var registrar: FlutterPluginRegistrar? = nil
    private var arkitView: FlutterArkitView?

    public static func register(with registrar: FlutterPluginRegistrar) {
        print("SwiftArkitPlugin.register called")
        SwiftArkitPlugin.registrar = registrar
        let arkitFactory = FlutterArkitFactory(messenger: registrar.messenger())
        registrar.register(arkitFactory, withId: "arkit")
        let channel = FlutterMethodChannel(name: "arkit_configuration", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(SwiftArkitPlugin(), channel: channel)
    }

    func setArkitView(_ view: FlutterArkitView) {
        self.arkitView = view
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arkitView = arkitView else {
            result(FlutterError(code: "NO_ARKIT_VIEW", message: "ARKit view not initialized", details: nil))
            return
        }

        switch call.method {
        case "checkConfiguration":
            let res = checkConfiguration(call.arguments)
            result(res)
        case "captureHighResImage":
            if #available(iOS 16.0, *) {
                captureHighResImage(arkitView: arkitView, result: result)
            } else {
                result(FlutterError(code: "UNSUPPORTED_IOS_VERSION", message: "High resolution capture requires iOS 15.0 or later", details: nil))
            }
        case "initCustomConfiguration":
            arkitView.configureSession(call.arguments as? [String: Any])
            result(nil)
        case "snapshotWithDepthData":
            if #available(iOS 14.0, *) {
                arkitView.snapshotWithDepthData(result)
            } else {
                // Fallback on earlier versions
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @available(iOS 16.0, *)
    private func captureHighResImage(arkitView: FlutterArkitView, result: @escaping FlutterResult) {
        arkitView.sceneView.session.captureHighResolutionFrame { (frame, error) in
            if let error = error {
                result(FlutterError(code: "HIGH_RES_CAPTURE_FAILED", message: error.localizedDescription, details: nil))
                return
            }
            guard let highResFrame = frame else {
                result(FlutterError(code: "NO_FRAME", message: "No high resolution frame captured", details: nil))
                return
            }
            let ciImage = CIImage(cvPixelBuffer: highResFrame.capturedImage)
            let context = CIContext(options: nil)
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                if let data = uiImage.pngData() {
                    result(data)
                } else {
                    result(FlutterError(code: "PNG_CONVERSION_FAILED", message: "Failed to convert image to PNG", details: nil))
                }
            } else {
                result(FlutterError(code: "CGIMAGE_CONVERSION_FAILED", message: "Failed to convert CIImage to CGImage", details: nil))
            }
        }
    }

    private func checkConfiguration(_ arguments: Any?) -> [String: Bool] {
        // Реализация checkConfiguration (оставь как есть или обнови, если нужно)
        return [:]
    }
}

class FlutterArkitFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        print("Creating FlutterArkitView with viewId: \(viewId)")
        let view = FlutterArkitView(withFrame: frame, viewIdentifier: viewId, messenger: messenger)
        SwiftArkitPlugin().setArkitView(view) // Сохраняем ссылку
        return view
    }
}

