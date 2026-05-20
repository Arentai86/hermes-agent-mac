import Foundation

struct HealthCheck {
    func ping(port: Int, token: String?) async -> Bool {
        if await ping(path: "/api/status", port: port, token: nil, acceptsAnyNonServerError: false) {
            return true
        }
        return await ping(path: "/", port: port, token: nil, acceptsAnyNonServerError: true)
    }

    private func ping(
        path: String,
        port: Int,
        token: String?,
        acceptsAnyNonServerError: Bool
    ) async -> Bool {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        components.path = path

        guard let url = components.url else { return false }

        var request = URLRequest(url: url, timeoutInterval: 1.5)
        if let token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return false }
            return acceptsAnyNonServerError ? statusCode < 500 : statusCode == 200
        } catch {
            return false
        }
    }
}
