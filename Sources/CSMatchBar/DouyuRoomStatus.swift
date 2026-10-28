import Foundation

enum DouyuRoomStatus: Equatable {
    case checking
    case live
    case offline
    case unavailable

    var title: String {
        switch self {
        case .checking: return "查询中"
        case .live: return "直播中"
        case .offline: return "未开播"
        case .unavailable: return "状态未知"
        }
    }
}

struct DouyuRoomClient {
    static let roomURL = URL(string: "https://www.douyu.com/6657")!
    // 6657 is the public alias; RoomApi requires the canonical room ID.
    static let roomID = "6979222"
    private static let statusURL = URL(string: "https://open.douyucdn.cn/api/RoomApi/room/\(roomID)")!

    enum StatusError: Error {
        case invalidResponse
    }

    func fetchStatus() async throws -> DouyuRoomStatus {
        var request = URLRequest(url: Self.statusURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw StatusError.invalidResponse
        }
        return try Self.parseStatus(data)
    }

    static func parseStatus(_ data: Data) throws -> DouyuRoomStatus {
        let response = try JSONDecoder().decode(RoomResponse.self, from: data)
        guard response.error == 0, let room = response.data, room.roomID.value == roomID else {
            throw StatusError.invalidResponse
        }
        switch room.status.value {
        case "1": return .live
        case "2": return .offline
        default: throw StatusError.invalidResponse
        }
    }

    private struct RoomResponse: Decodable {
        let error: Int
        let data: Room?

        // Error payloads can contain a message instead of the room object.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            error = try container.decode(Int.self, forKey: .error)
            data = error == 0 ? try container.decode(Room.self, forKey: .data) : nil
        }

        private enum CodingKeys: String, CodingKey {
            case error, data
        }
    }

    private struct Room: Decodable {
        let roomID: StringOrInt
        let status: StringOrInt

        private enum CodingKeys: String, CodingKey {
            case roomID = "room_id"
            case status = "room_status"
        }
    }

    private struct StringOrInt: Decodable {
        let value: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                value = string
            } else {
                value = String(try container.decode(Int.self))
            }
        }
    }
}
