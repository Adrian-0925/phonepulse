import Foundation
import Observation

struct SpeedTestEndpoints {
    let latency: URL
    let download: URL
    let upload: URL

    /// 仅供开发调试。Cloudflare 的公共测速地址不是给第三方 App 用的，
    /// 上线前必须换成自己的测速节点（国内用户建议用国内 CDN），否则速度不准且可能违反对方条款。
    static let development = SpeedTestEndpoints(
        latency: URL(string: "https://speed.cloudflare.com/__down?bytes=0")!,
        download: URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!,
        upload: URL(string: "https://speed.cloudflare.com/__up")!)
}

/// 主动测速：先测延迟，再下载、上传一段数据并计时。
/// TODO: 目前只在结束时给出结果；后续改用 URLSessionDataDelegate 做实时速度表盘，并支持多线程并发下载。
@MainActor
@Observable
final class SpeedTestService {
    enum Phase: Equatable {
        case idle, latency, download, upload, finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var latencyMs: Double?
    private(set) var downloadMbps: Double?
    private(set) var uploadMbps: Double?

    var isRunning: Bool { [Phase.latency, .download, .upload].contains(phase) }

    private let endpoints = SpeedTestEndpoints.development
    private let uploadBytes = 10_000_000
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    func run() async {
        guard !isRunning else { return }
        latencyMs = nil
        downloadMbps = nil
        uploadMbps = nil
        do {
            phase = .latency
            latencyMs = try await measureLatency()
            phase = .download
            downloadMbps = try await measureDownload()
            phase = .upload
            uploadMbps = try await measureUpload()
            phase = .finished
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// 取 5 次小请求中最快的一次
    private func measureLatency() async throws -> Double {
        var best = Double.infinity
        for _ in 0..<5 {
            let start = Date.now
            let (_, response) = try await session.data(from: endpoints.latency)
            try Self.check(response)
            best = min(best, Date.now.timeIntervalSince(start))
        }
        return best * 1000
    }

    private func measureDownload() async throws -> Double {
        let start = Date.now
        let (data, response) = try await session.data(from: endpoints.download)
        try Self.check(response)
        return Self.mbps(bytes: data.count, seconds: Date.now.timeIntervalSince(start))
    }

    private func measureUpload() async throws -> Double {
        var request = URLRequest(url: endpoints.upload)
        request.httpMethod = "POST"
        let payload = Data(count: uploadBytes)
        let start = Date.now
        let (_, response) = try await session.upload(for: request, from: payload)
        try Self.check(response)
        return Self.mbps(bytes: payload.count, seconds: Date.now.timeIntervalSince(start))
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func mbps(bytes: Int, seconds: TimeInterval) -> Double {
        seconds > 0 ? Double(bytes) * 8 / seconds / 1_000_000 : 0
    }
}
