// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Inspect the SDK before exposing SDK-specific names to the compiler. Availability
// checks handle older runtimes; this flag also permits builds with older SDKs.
let environment = ProcessInfo.processInfo.environment
let platformPath = "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
let explicitSDK = environment["SUMI_SDK_ROOT"] ?? environment["SDKROOT"]
let developerDirectory = environment["DEVELOPER_DIR"] ?? "/Applications/Xcode.app/Contents/Developer"
let sdkRoot = explicitSDK ?? {
    #if os(Linux)
    return FileManager.default.homeDirectoryForCurrentUser.path + "/.swiftpm/swift-sdks/darwin.artifactbundle/Developer/" + platformPath
    #else
    return developerDirectory + "/" + platformPath
    #endif
}()
let interfaceDirectory = sdkRoot + "/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/"
let interfaces = ["arm64e-apple-ios.swiftinterface", "arm64-apple-ios.swiftinterface", "arm64-apple-ios-simulator.swiftinterface", "x86_64-apple-ios-simulator.swiftinterface"]
let supportsLiquidGlass = environment["SUMI_DISABLE_LIQUID_GLASS"] != "1" && interfaces.contains { name in
    guard let contents = try? String(contentsOfFile: interfaceDirectory + name, encoding: .utf8) else { return false }
    return contents.contains("func glassEffect(") && contents.contains("struct GlassEffectContainer<")
}

let package = Package(
    name: "Sumi",
    platforms: [.iOS(.v17)],
    products: [.library(name: "Sumi", targets: ["Sumi"])],
    targets: [.target(name: "Sumi", resources: [.process("Resources")],
                      swiftSettings: supportsLiquidGlass ? [.define("LIQUID_GLASS")] : [])],
    swiftLanguageModes: [.v5]
)
