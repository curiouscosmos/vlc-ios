/* Copyright (c) 2026 Sandalbar Enterprises, Inc. GPLv2 or later; see COPYING. */
import Foundation

struct DiscourseCaption: Equatable {
    let start: Double
    let end: Double
    let text: String
}

enum DiscourseCaptions {
    static func parse(_ source: String) -> [DiscourseCaption] {
        let source = source.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n[ \t]+\n", with: "\n\n", options: .regularExpression)
        return source.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let index = lines.firstIndex(where: { $0.contains(" --> ") }) else { return nil }
            let times = lines[index].components(separatedBy: " --> ")
            guard times.count == 2, let start = timestamp(times[0]), let end = timestamp(times[1]), end > start else { return nil }
            let text = lines.dropFirst(index + 1).joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return DiscourseCaption(start: start, end: end, text: text)
        }.sorted { $0.start < $1.start }
    }

    static func srt(_ captions: [DiscourseCaption], start: Double, end: Double) -> String {
        guard start.isFinite, end.isFinite, start >= 0, end > start else { return "" }
        func time(_ seconds: Double) -> String {
            let ms = Int64((max(0, seconds) * 1000).rounded())
            return String(format: "%02lld:%02lld:%02lld,%03lld", ms / 3600000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000)
        }
        var cues: [String] = []
        for caption in captions where caption.start < end && caption.end > start {
            let from = max(start, caption.start) - start
            let to = min(end, caption.end) - start
            guard (to * 1000).rounded() > (from * 1000).rounded() else { continue }
            cues.append("\(cues.count + 1)\n\(time(from)) --> \(time(to))\n\(caption.text)\n")
        }
        return cues.joined(separator: "\n")
    }

    private static func timestamp(_ raw: String) -> Double? {
        let parts = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").components(separatedBy: ":")
        guard parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]),
              hours.isFinite, minutes.isFinite, seconds.isFinite, hours >= 0, hours.rounded() == hours,
              minutes >= 0, minutes < 60, minutes.rounded() == minutes, seconds >= 0, seconds < 60 else { return nil }
        let value = hours * 3600 + minutes * 60 + seconds
        return value.isFinite ? value : nil
    }

    static func activeIndex(in captions: [DiscourseCaption], at time: Double) -> Int? {
        // Binary search keeps long discourse transcripts cheap on every player tick.
        var lower = 0
        var upper = captions.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if captions[middle].start <= time { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0, time < captions[lower - 1].end else { return nil }
        return lower - 1
    }
}

final class DiscourseCaptionLoader {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func load(url: URL, forceRefresh: Bool = false) async throws -> [DiscourseCaption] {
        try Task.checkCancellation()
        let request = URLRequest(url: url, cachePolicy: forceRefresh ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad, timeoutInterval: 30)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              data.count <= 10 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        let captions = DiscourseCaptions.parse(text)
        guard !captions.isEmpty else { throw URLError(.cannotParseResponse) }
        session.configuration.urlCache?.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
        return captions
    }
}
