import Foundation

public actor DiscoveryParser {
    public init() {}

    public func parseAnnouncement(_ data: Data, sourceHost: String) -> DiscoveredRadio? {
        guard let body = String(data: data, encoding: .utf8) else {
            return nil
        }

        let properties = body
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .reduce(into: [String: String]()) { result, line in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    result[parts[0].lowercased()] = parts[1]
                }
            }

        guard let nickname = properties["nickname"] ?? properties["name"],
              let model = properties["model"] else {
            return nil
        }

        let id = properties["serial"] ?? "\(sourceHost)-\(nickname)"
        return DiscoveredRadio(id: id, nickname: nickname, model: model, host: sourceHost, serial: properties["serial"])
    }
}
