import Foundation

public enum Greeting {
    public static func hello() -> String {
        "Hello from Core (macOS)!"
    }

    public static func greet(name: String) -> String {
        "Hello, \(name)!"
    }
}
