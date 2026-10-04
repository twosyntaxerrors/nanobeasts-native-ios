#!/usr/bin/env python3
"""Verify cached Watch appearance, fallback, and message ordering with isolated defaults."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
style = (root / 'NanobeastsWatch/WatchWorkoutStyle.swift').read_text().split('enum WatchNanoStyle {')[0]
checks = r'''
@main struct AppearanceChecks {
    @MainActor static func main() throws {
        let suite = "nano-watch-appearance-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WatchAppearanceStore(defaults: defaults)
        var count = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message); count += 1
        }
        check(store.appearance == nil, "Fresh Watch has no inferred phone choice")
        check(store.color == NanoAccent.mint.secondaryColor, "Fresh Watch uses Nanobeasts cyan")
        let encoder = JSONEncoder()
        let start = Date(timeIntervalSince1970: 1000)
        for (index, accent) in NanoAccent.allCases.enumerated() {
            let snapshot = WatchInterfaceAppearance(accentName: accent.rawValue,
                updatedAt: start.addingTimeInterval(Double(index)))
            store.receive(try encoder.encode(snapshot))
            check(store.color == accent.color, "Exact shared color for " + accent.rawValue)
        }
        let reloaded = WatchAppearanceStore(defaults: defaults)
        check(reloaded.appearance?.accentName == "blue", "Last phone choice survives relaunch")
        check(reloaded.color == NanoAccent.blue.color, "Offline color stays selected")
        reloaded.receive(try encoder.encode(WatchInterfaceAppearance(accentName: "pink", updatedAt: start)))
        check(reloaded.color == NanoAccent.blue.color, "Old context cannot revert newer choice")
        reloaded.receive(try encoder.encode(WatchInterfaceAppearance(accentName: "gold", updatedAt: start.addingTimeInterval(5))))
        check(reloaded.color == NanoAccent.blue.color, "Duplicate timestamp cannot overwrite choice")
        reloaded.receive(Data("not JSON".utf8))
        check(reloaded.color == NanoAccent.blue.color, "Malformed message preserves last choice")
        reloaded.receive(try encoder.encode(WatchInterfaceAppearance(accentName: "future-color", updatedAt: start.addingTimeInterval(6))))
        check(reloaded.color == NanoAccent.mint.secondaryColor, "Unknown future color uses cyan")
        print("Passed \(count) Watch appearance checks")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='nano-watch-appearance-') as tmp:
    folder = pathlib.Path(tmp)
    source = folder / 'Checks.swift'
    source.write_text('\n'.join([
        (root / 'NanobeastsShared/NanoAccent.swift').read_text(),
        (root / 'NanobeastsShared/WatchWorkoutMessage.swift').read_text(), style, checks]))
    binary = folder / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(folder / 'ModuleCache'), str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
