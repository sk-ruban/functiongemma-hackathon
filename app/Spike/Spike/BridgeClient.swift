import Foundation

final class BridgeClient: Sendable {
    private let baseURL = URL(string: "http://127.0.0.1:8420")!

    func checkHealth() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["status"] as? String == "ok"
        } catch {
            return false
        }
    }

    func transcribeAndAct(audioFileURL: URL) async throws -> BridgeResponse {
        let url = baseURL.appendingPathComponent("transcribe_and_act")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioFileURL)
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let serverMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw BridgeError.httpError(statusCode, serverMessage)
        }

        return try JSONDecoder().decode(BridgeResponse.self, from: data)
    }
}

enum BridgeError: LocalizedError {
    case httpError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let detail):
            if let detail { return detail }
            return "Bridge server returned HTTP \(code)"
        }
    }
}
