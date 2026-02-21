import Foundation

struct BridgeResponse: Codable, Sendable {
    let transcription: String
    let functionCalls: [ToolCall]
    let source: String
    let confidence: Double
    let totalTimeMs: Double
    let transcriptionTimeMs: Double
    let routingTimeMs: Double
    let error: String?

    enum CodingKeys: String, CodingKey {
        case transcription
        case functionCalls = "function_calls"
        case source
        case confidence
        case totalTimeMs = "total_time_ms"
        case transcriptionTimeMs = "transcription_time_ms"
        case routingTimeMs = "routing_time_ms"
        case error
    }
}

struct ToolCall: Codable, Sendable, Identifiable {
    let name: String
    let arguments: [String: String]

    var id: String { name + arguments.description }
}

struct ActionResult: Identifiable, Sendable {
    let id = UUID()
    let toolName: String
    let success: Bool
    let message: String
}
