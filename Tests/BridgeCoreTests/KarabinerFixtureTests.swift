import Foundation
import Carbon
import Testing
import BridgeCore

struct KarabinerFixtureTests {
    private let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "s": kVK_ANSI_S, "d": kVK_ANSI_D, "f": kVK_ANSI_F, "g": kVK_ANSI_G,
        "z": kVK_ANSI_Z, "x": kVK_ANSI_X, "c": kVK_ANSI_C, "v": kVK_ANSI_V, "b": kVK_ANSI_B,
        "q": kVK_ANSI_Q, "w": kVK_ANSI_W, "e": kVK_ANSI_E, "r": kVK_ANSI_R, "y": kVK_ANSI_Y,
        "t": kVK_ANSI_T, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "l": kVK_ANSI_L, "n": kVK_ANSI_N,
        "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
        "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, "0": kVK_ANSI_0,
        "equal_sign": kVK_ANSI_Equal, "hyphen": kVK_ANSI_Minus, "comma": kVK_ANSI_Comma,
        "open_bracket": kVK_ANSI_LeftBracket, "close_bracket": kVK_ANSI_RightBracket,
        "return_or_enter": kVK_Return, "delete_or_backspace": kVK_Delete, "delete_forward": kVK_ForwardDelete,
        "escape": kVK_Escape, "home": kVK_Home, "end": kVK_End, "f2": kVK_F2,
        "left_arrow": kVK_LeftArrow, "right_arrow": kVK_RightArrow, "up_arrow": kVK_UpArrow, "down_arrow": kVK_DownArrow
    ]
    private func modifiers(_ names: [String]) throws -> Modifiers {
        var result: Modifiers = []
        let groups: [String: Modifiers] = ["control": .control, "command": .command, "option": .option, "shift": .shift, "fn": .fn]
        for name in names {
            let group = name.replacingOccurrences(of: "left_", with: "").replacingOccurrences(of: "right_", with: "")
            result.insert(try #require(groups[group]))
        }
        return result
    }
    @Test func compiledRulesMatchOriginalUserFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "windows-like-mac-v2", withExtension: "json", subdirectory: "Fixtures"))
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let rules = try #require(root["manipulators"] as? [[String: Any]])
        #expect(rules.count == 78)
        // #1–4 are control/scope policies, #5–10 and #77 require a hardware backend.
        // #63 is the conditional move branch of the #64 Finder paste transaction.
        let compiled = WindowsCompatibilityRules.system + WindowsCompatibilityRules.general +
            WindowsCompatibilityRules.browser + WindowsCompatibilityRules.finder
        #expect(compiled.count == 66)
        let legacyIDs = [13: "copy", 14: "paste", 15: "cut", 16: "selectAll", 17: "undo", 18: "redo", 19: "save", 21: "find", 22: "print"]
        for number in 11...78 where number != 63 && number != 77 {
            let fixture = rules[number - 1]
            let from = try #require(fixture["from"] as? [String: Any])
            let inputName = try #require(from["key_code"] as? String)
            let inputKey = try #require(keyCodes[inputName])
            let inputMods = (from["modifiers"] as? [String: Any])?["mandatory"] as? [String] ?? []
            let id = legacyIDs[number].map { "windows.\($0)" } ?? String(format: "karabiner.%02d", number)
            let rule = try #require(compiled.first { $0.id == id })
            #expect(rule.input.keyCode == UInt16(inputKey))
            #expect(rule.input.modifiers == (try modifiers(inputMods)))
            let targets = try #require(fixture["to"] as? [[String: Any]])
            if let output = targets.first(where: { $0["key_code"] != nil }) {
                let outputName = try #require(output["key_code"] as? String)
                let outputKey = try #require(keyCodes[outputName])
                #expect(rule.output.keyCode == UInt16(outputKey))
                #expect(rule.output.modifiers == (try modifiers(output["modifiers"] as? [String] ?? [])))
            } else {
                #expect(number == 12 || number == 78)
                #expect(rule.action == .system(number == 12 ? .openFinder : .activityMonitor))
            }
        }
        let move = try #require((rules[62]["to"] as? [[String: Any]])?.first)
        #expect(move["key_code"] as? String == "v")
        #expect(try modifiers(move["modifiers"] as? [String] ?? []) == [.command, .option])
    }
}
