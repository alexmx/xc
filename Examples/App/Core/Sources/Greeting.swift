import Foundation

public enum Greeting {
    public static func hello() -> String {
        "Hello from Core!"
    }

    public static func greet(name: String) -> String {
        "Hello, \(name)!"
    }
}
