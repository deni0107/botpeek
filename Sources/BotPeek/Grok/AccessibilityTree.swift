#if canImport(AppKit)
import AppKit
import ApplicationServices
import BotPeekCore

/// A copied Accessibility tree plus a side table back to the live elements.
struct AXSnapshot {
    let root: AXNodeSnapshot
    let elements: [Int: AXUIElement]

    func element(_ id: Int?) -> AXUIElement? {
        id.flatMap { elements[$0] }
    }
}

/// Thin, synchronous wrappers around the Accessibility C API.
///
/// These calls are IPC into Grok Bot. They are safe to run off the main
/// thread, and BotPeek does so for whole-tree reads to keep its UI smooth.
enum AXTree {
    static let maximumNodes = 5_000
    static let maximumDepth = 45

    private static let attributes = [
        kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXChildrenAttribute,
    ] as CFArray

    static func copy(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var result: [AXUIElement] = []
        if let main = copy(app, kAXMainWindowAttribute), CFGetTypeID(main) == AXUIElementGetTypeID() {
            result.append(unsafeDowncast(main, to: AXUIElement.self))
        }
        if let all = copy(app, kAXWindowsAttribute) as? [AXUIElement] {
            result.append(contentsOf: all.filter { candidate in !result.contains { CFEqual($0, candidate) } })
        }
        return result
    }

    /// Chromium only builds its web-content Accessibility tree when asked.
    /// Electron apps treat `AXManualAccessibility` as that request.
    static func enableManualAccessibility(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Breadth-first copy of the tree under `root`.
    static func snapshot(_ root: AXUIElement) -> AXSnapshot {
        struct Pending {
            let element: AXUIElement
            let id: Int
            let depth: Int
        }
        var elements: [Int: AXUIElement] = [0: root]
        var records: [Int: (role: String, title: String?, description: String?, value: String?, children: [Int])] = [:]
        var queue = [Pending(element: root, id: 0, depth: 0)]
        var index = 0
        var nextID = 1

        while index < queue.count {
            let item = queue[index]
            index += 1
            var values: CFArray?
            AXUIElementCopyMultipleAttributeValues(item.element, attributes, [], &values)
            let list = (values as? [AnyObject]) ?? []
            func value(at position: Int) -> AnyObject? {
                guard position < list.count else { return nil }
                let raw = list[position]
                // Missing attributes come back as AXValue error placeholders.
                if CFGetTypeID(raw) == AXValueGetTypeID() { return nil }
                return raw
            }
            var childIDs: [Int] = []
            if item.depth < maximumDepth, let children = value(at: 4) as? [AXUIElement] {
                for child in children where nextID < maximumNodes {
                    elements[nextID] = child
                    childIDs.append(nextID)
                    queue.append(Pending(element: child, id: nextID, depth: item.depth + 1))
                    nextID += 1
                }
            }
            records[item.id] = (
                role: (value(at: 0) as? String) ?? "",
                title: value(at: 1) as? String,
                description: value(at: 2) as? String,
                value: value(at: 3) as? String,
                children: childIDs
            )
        }

        func build(_ id: Int) -> AXNodeSnapshot {
            let record = records[id] ?? (role: "", title: nil, description: nil, value: nil, children: [])
            return AXNodeSnapshot(
                id: id,
                role: record.role,
                title: record.title,
                axDescription: record.description,
                value: record.value,
                children: record.children.map(build)
            )
        }
        return AXSnapshot(root: build(0), elements: elements)
    }

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    @discardableResult
    static func focus(_ element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    static func setValue(_ element: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString) == .success
    }
}
#endif
