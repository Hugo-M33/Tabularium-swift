import Combine
import SwiftUI

/// Un dossier raccourci choisi par l'utilisateur (premium).
struct FolderShortcut: Codable, Identifiable, Hashable {
    let id: String      // localIdentifier de l'album
    let title: String
}

/// Préférences premium : 3 dossiers raccourcis + action de chaque direction de
/// swipe (cartes & flux). Persistées dans UserDefaults.
@MainActor
final class GestureSettings: ObservableObject {

    /// Action déclenchée par un geste (ou un bouton).
    enum Action: Hashable {
        case keep, delete, none
        case folder(String)   // localIdentifier de l'album

        var raw: String {
            switch self {
            case .keep: return "keep"
            case .delete: return "delete"
            case .none: return "none"
            case .folder(let id): return "folder:\(id)"
            }
        }
        init(raw: String) {
            switch raw {
            case "keep": self = .keep
            case "delete": self = .delete
            case "none": self = .none
            default:
                if raw.hasPrefix("folder:") { self = .folder(String(raw.dropFirst(7))) }
                else { self = .none }
            }
        }
        var folderID: String? { if case .folder(let id) = self { return id } else { return nil } }
    }

    static let maxShortcuts = 3

    @Published var shortcuts: [FolderShortcut] { didSet { persistShortcuts() } }
    @Published var cardsRight: Action { didSet { d.set(cardsRight.raw, forKey: K.cardsRight) } }
    @Published var cardsLeft: Action  { didSet { d.set(cardsLeft.raw, forKey: K.cardsLeft) } }
    @Published var feedRight: Action  { didSet { d.set(feedRight.raw, forKey: K.feedRight) } }
    @Published var feedLeft: Action   { didSet { d.set(feedLeft.raw, forKey: K.feedLeft) } }

    private let d = UserDefaults.standard
    private enum K {
        static let shortcuts = "gestures.shortcuts"
        static let cardsRight = "gestures.cardsRight"
        static let cardsLeft = "gestures.cardsLeft"
        static let feedRight = "gestures.feedRight"
        static let feedLeft = "gestures.feedLeft"
    }

    init() {
        let data = d.data(forKey: K.shortcuts) ?? Data()
        shortcuts = (try? JSONDecoder().decode([FolderShortcut].self, from: data)) ?? []
        cardsRight = Action(raw: d.string(forKey: K.cardsRight) ?? "keep")
        cardsLeft  = Action(raw: d.string(forKey: K.cardsLeft) ?? "delete")
        feedRight  = Action(raw: d.string(forKey: K.feedRight) ?? "delete")
        feedLeft   = Action(raw: d.string(forKey: K.feedLeft) ?? "delete")
    }

    private func persistShortcuts() {
        d.set(try? JSONEncoder().encode(shortcuts), forKey: K.shortcuts)
    }

    func title(forFolder id: String) -> String? {
        shortcuts.first { $0.id == id }?.title
    }

    /// Neutralise les actions pointant vers un dossier qui n'est plus un raccourci.
    func sanitizeActions() {
        let ids = Set(shortcuts.map(\.id))
        func fix(_ a: Action) -> Action {
            if case .folder(let id) = a, !ids.contains(id) { return .none }
            return a
        }
        if fix(cardsRight) != cardsRight { cardsRight = fix(cardsRight) }
        if fix(cardsLeft)  != cardsLeft  { cardsLeft  = fix(cardsLeft) }
        if fix(feedRight)  != feedRight  { feedRight  = fix(feedRight) }
        if fix(feedLeft)   != feedLeft   { feedLeft   = fix(feedLeft) }
    }
}
