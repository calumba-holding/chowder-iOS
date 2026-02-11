import Foundation

struct UserContext: Codable {
    // Fixed fields — common things OpenClaw might know about the user
    var name: String = ""
    var location: String = ""
    var bio: String = ""

    // Flexible key-value pairs for anything else
    var extras: [String: String] = [:]
}
