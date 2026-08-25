import Foundation

public enum CardType: String, Codable, CaseIterable, Sendable {
    case cloze
    case definition
    case appreciation
}
