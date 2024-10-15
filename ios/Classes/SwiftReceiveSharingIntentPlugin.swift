import Flutter
import UIKit
import Photos

public class SwiftReceiveSharingIntentPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let kMessagesChannel = "receive_sharing_intent/messages";
    static let kEventsChannelMedia = "receive_sharing_intent/events-media";
    static let kEventsChannelLink = "receive_sharing_intent/events-text";
        
    private var initialMedia: [SharedMediaFile]? = nil
    private var latestMedia: [SharedMediaFile]? = nil
    
    private var initialText: String? = nil
    private var latestText: String? = nil
    
    private var eventSinkMedia: FlutterEventSink? = nil;
    private var eventSinkText: FlutterEventSink? = nil;
    
    // Singleton is required for calling functions directly from AppDelegate
    // - it is required if the developer is using also another library, which requires to call "application(_:open:options:)"
    // -> see Example app
    public static let instance = SwiftReceiveSharingIntentPlugin()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: kMessagesChannel, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        let chargingChannelMedia = FlutterEventChannel(name: kEventsChannelMedia, binaryMessenger: registrar.messenger())
        chargingChannelMedia.setStreamHandler(instance)
        
        let chargingChannelLink = FlutterEventChannel(name: kEventsChannelLink, binaryMessenger: registrar.messenger())
        chargingChannelLink.setStreamHandler(instance)
        
        registrar.addApplicationDelegate(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getInitialMedia":
            result(toJson(data: self.initialMedia));
        case "getInitialText":
            result(self.initialText);
        case "reset":
            self.initialMedia = nil
            self.latestMedia = nil
            self.initialText = nil
            self.latestText = nil
            result(nil);
        default:
            result(FlutterMethodNotImplemented);
        }
    }
    
    // This is the function called on app startup with a shared link if the app had been closed already.
    // It is called as the launch process is finishing and the app is almost ready to run.
    // If the URL includes the module's ShareMedia prefix, then we process the URL and return true if we know how to handle that kind of URL or false if the app is not able to.
    // If the URL does not include the module's prefix, we must return true since while our module cannot handle the link, other modules might be and returning false can prevent
    // them from getting the chance to.
    // Reference: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622921-application
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if let url = launchOptions?[UIApplication.LaunchOptionsKey.url] as? URL {
            if (url.isFileURL) {
                return handleUrl(url: url, setInitialData: true)
            }
        }

        return true
    }
    
    // This is the function called on resuming the app from a shared link.
    // It handles requests to open a resource by a specified URL. Returning true means that it was handled successfully, false means the attempt to open the resource failed.
    // If the URL includes the module's ShareMedia prefix, then we process the URL and return true if we know how to handle that kind of URL or false if we are not able to.
    // If the URL does not include the module's prefix, then we return false to indicate our module's attempt to open the resource failed and others should be allowed to.
    // Reference: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623112-application
    public func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return handleUrl(url: url, setInitialData: true)
    }
    
    // This function is called by other modules like Firebase DeepLinks.
    // It tells the delegate that data for continuing an activity is available. Returning true means that our module handled the activity and that others do not have to. Returning false tells
    // iOS that our app did not handle the activity.
    // If the URL includes the module's ShareMedia prefix, then we process the URL and return true if we know how to handle that kind of URL or false if we are not able to.
    // If the URL does not include the module's prefix, then we must return false to indicate that this module did not handle the prefix and that other modules should try to.
    // Reference: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623072-application
    public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]) -> Void) -> Bool {
        if let url = userActivity.webpageURL {
            return handleUrl(url: url, setInitialData: true)
        }
        return false
    }
    
    private func handleUrl(url: URL, setInitialData: Bool) -> Bool {
        if url.isFileURL {
            // Check if the app already has permission to read the file directly
            if FileManager.default.isReadableFile(atPath: url.path) {
                
                // Return the file path directly
                latestMedia = [SharedMediaFile(path: url.path, thumbnail: nil, duration: nil, type: .file)]
                
                if setInitialData {
                    initialMedia = latestMedia
                }
                
                eventSinkMedia?(toJson(data: latestMedia))
                return true
            }
            
            // Workaround to avoid file exceptions (read permission errors) when trying to read the file in Dart code.
            // By copying the file to a temp directory that the app has direct access to, we avoid running into security-scoped resource issues.
            // The Dart code will then have consistent access to the file, bypassing the need for security-scoped resource access.
            // Perform the file copy on a background queue to avoid blocking the main thread
            if url.startAccessingSecurityScopedResource() {
                defer {
                    // Ensure we stop accessing the resource once we're done
                    url.stopAccessingSecurityScopedResource()
                }
                
                // Now it's safe to access the file
                let sourcePath = getAbsolutePath(for: url.path)
                let fileManager = FileManager.default
                let tempDirectoryURL = fileManager.temporaryDirectory
                let fileName = url.lastPathComponent
                let destinationURL = tempDirectoryURL.appendingPathComponent(fileName)
                
                do {
                    // If the file already exists, remove it before copying
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                                    
                    // Copy the file to the temp directory
                    try fileManager.copyItem(at: url, to: destinationURL)
                    
                    // Update the latest media to point to the copied file
                    latestMedia = [SharedMediaFile(path: destinationURL.path, thumbnail: nil, duration: nil, type: .file)]
                    
                    if setInitialData {
                        initialMedia = latestMedia
                    }
                    
                    eventSinkMedia?(toJson(data: latestMedia))
                } catch {
                    print("Error copying file: \(error.localizedDescription)")
                    return false
                }
            } else {
                print("Failed to access security-scoped resource")
                return false
            }
        }
        
        latestMedia = nil
        latestText = nil
        return true
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        if (arguments as! String? == "media") {
            eventSinkMedia = events;
        } else if (arguments as! String? == "text") {
            eventSinkText = events;
        } else {
            return FlutterError.init(code: "NO_SUCH_ARGUMENT", message: "No such argument\(String(describing: arguments))", details: nil);
        }
        return nil;
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if (arguments as! String? == "media") {
            eventSinkMedia = nil;
        } else if (arguments as! String? == "text") {
            eventSinkText = nil;
        } else {
            return FlutterError.init(code: "NO_SUCH_ARGUMENT", message: "No such argument as \(String(describing: arguments))", details: nil);
        }
        return nil;
    }
    
    private func getAbsolutePath(for identifier: String) -> String {
        if (identifier.starts(with: "file://")) {
            return identifier.replacingOccurrences(of: "file://", with: "")
        }
        return identifier;
    }
    
    private func toJson(data: [SharedMediaFile]?) -> String? {
        if data == nil {
            return nil
        }
        let encodedData = try? JSONEncoder().encode(data)
         let json = String(data: encodedData!, encoding: .utf8)!
        return json
    }
    
    class SharedMediaFile: Codable {
        var path: String;
        var thumbnail: String?; // video thumbnail
        var duration: Double?; // video duration in milliseconds
        var type: SharedMediaType;

        
        init(path: String, thumbnail: String?, duration: Double?, type: SharedMediaType) {
            self.path = path
            self.thumbnail = thumbnail
            self.duration = duration
            self.type = type
        }
    }
    
    enum SharedMediaType: Int, Codable {
        case image
        case video
        case file
    }
}
