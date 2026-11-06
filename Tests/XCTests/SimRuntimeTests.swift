import Testing
@testable import xc

@Suite("SimRuntime Tests")
struct SimRuntimeTests {
    private let prefix = "com.apple.CoreSimulator.SimRuntime."

    @Test("labels a runtime as platform and version", arguments: [
        ("iOS-18-5", "iOS 18.5"),
        ("tvOS-18-0", "tvOS 18.0"),
        ("watchOS-11-2", "watchOS 11.2"),
        ("xrOS-2-3", "xrOS 2.3"),
        ("iOS-26", "iOS 26")
    ])
    func displayName(id: String, label: String) {
        #expect(SimRuntime(id: prefix + id).displayName == label)
    }

    @Test("a device-specific runtime keeps its model as a label, not as version numbers")
    func deviceSpecific() {
        let runtime = SimRuntime(id: prefix + "iOS-27-2-iPhone19-4")
        #expect(runtime.platform == "iOS")
        #expect(runtime.version == [27, 2])
        #expect(runtime.device == "iPhone19,4")
        #expect(runtime.displayName == "iOS 27.2 (iPhone19,4)")
    }

    @Test("versions compare as numbers")
    func versionOrder() {
        #expect(SimRuntime(id: prefix + "iOS-9-3") < SimRuntime(id: prefix + "iOS-26-0"))
        #expect(SimRuntime(id: prefix + "iOS-26-2") < SimRuntime(id: prefix + "iOS-26-10"))
    }

    @Test("init picks a Pro iPhone from the newest standard runtime, not a device-specific one")
    func defaultiPhone() {
        let runtimes = [
            prefix + "iOS-27-2-iPhone19-4": ["iPhone Duo"],
            prefix + "iOS-27-2": ["iPhone 18 Pro", "iPhone 18 Pro Max", "iPhone 17e", "iPhone Air"],
            prefix + "iOS-9-3": ["iPhone 6s Pro"]
        ]
        #expect(InitCommand.defaultiPhone(in: runtimes) == "iPhone 18 Pro")
    }

    @Test("init falls back to any iPhone, then to a device-specific runtime")
    func defaultiPhoneFallbacks() {
        #expect(InitCommand.defaultiPhone(in: [prefix + "iOS-27-2": ["iPhone Air"]]) == "iPhone Air")
        #expect(InitCommand.defaultiPhone(in: [prefix + "iOS-27-2-iPhone19-4": ["iPhone Duo"]]) == "iPhone Duo")
        #expect(InitCommand.defaultiPhone(in: [prefix + "tvOS-18-0": ["Apple TV"]]) == nil)
    }

    @Test("destination platforms come from the runtime's platform", arguments: [
        ("iOS-26-0", "iOS Simulator"),
        ("iOS-27-2-iPhone19-4", "iOS Simulator"),
        ("tvOS-18-0", "tvOS Simulator"),
        ("watchOS-11-2", "watchOS Simulator"),
        ("xrOS-2-3", "visionOS Simulator"),
        ("fooOS-1-0", "fooOS 1.0")
    ])
    func destinationPlatform(id: String, platform: String) {
        #expect(SimRuntime(id: prefix + id).destinationPlatform == platform)
    }
}
