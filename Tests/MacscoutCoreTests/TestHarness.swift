import Darwin
import Dispatch
// `import Testing` is kept only so SwiftPM selects its swiftpm-testing-helper
// runner for this bundle. This CLT-only toolchain's Testing.framework is a
// stub: it discovers @Test functions but swallows #expect failures, traps and
// even exit() without ever failing `swift test`. The harness below therefore
// runs the suite itself when the bundle is loaded (ObjC +load inside the
// helper process), prints results, and terminates the process with a non-zero
// status on any failure.
import Testing

typealias TestBody = () throws -> Void

private var registeredTests: [(name: String, body: TestBody)] = []
private(set) var checkCount = 0
private var failedChecks: [String] = []

/// Register a named suite of tests.
func register(_ suite: String, _ tests: [(String, TestBody)]) {
    for (name, body) in tests {
        registeredTests.append(("\(suite).\(name)", body))
    }
}

/// Assert a condition.
func check(_ condition: Bool, _ message: @autoclosure () -> String = "check failed",
           file: StaticString = #filePath, line: UInt = #line) {
    checkCount += 1
    if !condition {
        let shortFile = String(describing: file).split(separator: "/").last.map(String.init) ?? "?"
        failedChecks.append("\(shortFile):\(line): \(message())")
    }
}

/// Assert equality.
func checkEqual<T: Equatable>(_ actual: T, _ expected: T,
                              file: StaticString = #filePath, line: UInt = #line) {
    check(actual == expected, "expected \(expected), got \(actual)", file: file, line: line)
}

/// Assert equality with a custom message.
func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: @autoclosure () -> String,
                              file: StaticString = #filePath, line: UInt = #line) {
    check(actual == expected, message(), file: file, line: line)
}

/// Assert a Double equality within tolerance.
func checkClose(_ actual: Double, _ expected: Double, tolerance: Double = 0.0001,
                file: StaticString = #filePath, line: UInt = #line) {
    check(abs(actual - expected) <= tolerance,
          "expected \(expected) ±\(tolerance), got \(actual)", file: file, line: line)
}

/// Assert an optional is non-nil and return the unwrapped value.
func unwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
    check(value != nil, "unexpected nil", file: file, line: line)
    return value!
}

/// Run an async test body synchronously.
func sync(_ body: @escaping () async throws -> Void) -> TestBody {
    nonisolated(unsafe) let body = body
    return {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var thrown: Error?
        Task {
            do { try await body() } catch { thrown = error }
            sem.signal()
        }
        sem.wait()
        if let thrown { throw thrown }
    }
}

/// Execute all registered tests; returns (passed, failed) test counts.
func runAllTests() -> (Int, Int) {
    var passed = 0, failed = 0
    for test in registeredTests {
        let failuresBefore = failedChecks.count
        do {
            try test.body()
        } catch {
            failedChecks.append("\(test.name): threw \(error)")
        }
        if failedChecks.count == failuresBefore {
            passed += 1
            print("  ✓ \(test.name)")
        } else {
            failed += 1
            print("  ✗ \(test.name)")
            for message in failedChecks[failuresBefore...] {
                print("      \(message)")
            }
        }
    }
    return (passed, failed)
}



/// Runs the suite at image load time (when SwiftPM's testing helper dlopens
/// the bundle), before the toolchain's no-op Testing entry point.
/// Emits a pointer into __mod_init_func, the same mechanism C constructors use.
