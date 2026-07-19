import Foundation

// Test bootstrap for the CLT-only toolchain (no XCTest, broken swift-testing
// runner). The suite runs when SwiftPM's testing helper dlopens this bundle:
//
// 1. The mod_init constructor runs all non-network suites in-process.
// 2. URLSession-based client tests cannot run inside a dlopen constructor
//    (CFNetwork initialization deadlocks against the dyld lock), so the
//    constructor spawns MacscoutCoreTestsRunner — a tiny executable which
//    dlopens this same bundle in a fresh process and, after dlopen returns,
//    calls `macscout_run_client_tests`.
// 3. Any failure exits the process with a non-zero status, failing
//    `swift test`.

/// Runs the registered client (network) suites; called from the runner
/// executable in a fresh process where URLSession works normally.
/// Returns the number of failed tests.
@_cdecl("macscout_run_client_tests")
public func macscoutRunClientTests() -> Int32 {
    setbuf(stdout, nil)
    registerClientTests()
    let (passed, failed) = runAllTests()
    print("MacscoutCoreTests(client): \(passed) passed, \(failed) failed")
    fflush(stdout)
    return Int32(failed)
}

@_cdecl("macscout_test_bootstrap")
private func macscoutTestBootstrapImpl() {
    setbuf(stdout, nil)

    // Inside the child runner process: only dlopen + return here; the runner
    // calls macscout_run_client_tests itself once the dyld lock is released.
    if ProcessInfo.processInfo.environment["MACSCOUT_CHILD"] == "1" {
        return
    }

    registerLocalTests()
    print("MacscoutCoreTests")
    let (passed, failed) = runAllTests()
    print("MacscoutCoreTests: \(passed) passed, \(failed) failed, \(checkCount) checks")
    fflush(stdout)

    var childFailed = 0
    if let bundlePath = selfImagePath(), let runner = runnerPath(nextTo: bundlePath) {
        childFailed = runChild(runner: runner, bundle: bundlePath)
    } else {
        print("MacscoutCoreTests: could not locate MacscoutCoreTestsRunner (bundle: \(selfImagePath() ?? "?")), skipping client tests")
    }

    if failed > 0 || childFailed > 0 {
        Darwin.exit(1)
    }
}

@_used
@_section("__DATA,__mod_init_func")
private let macscoutTestBootstrap: @convention(c) () -> Void = macscoutTestBootstrapImpl

/// Absolute path of this image (the test bundle binary).
private func selfImagePath() -> String? {
    var info = Dl_info()
    guard dladdr(#dsohandle, &info) != 0, let path = info.dli_fname else { return nil }
    return String(cString: path)
}

/// `<.build/debug>/MacscoutCoreTestsRunner` derived from
/// `<.build/debug>/MacscoutPackageTests.xctest/Contents/MacOS/MacscoutPackageTests`.
private func runnerPath(nextTo bundlePath: String) -> String? {
    var url = URL(fileURLWithPath: bundlePath)
    url.deleteLastPathComponent() // binary → MacOS
    url.deleteLastPathComponent() // MacOS → Contents
    url.deleteLastPathComponent() // Contents → .xctest
    url.deleteLastPathComponent() // .xctest → debug build dir
    let candidate = url.appendingPathComponent("MacscoutCoreTestsRunner").path
    return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
}

/// Spawn the runner executable with the bundle path; returns its exit status.
private func runChild(runner: String, bundle: String) -> Int {
    var pid = pid_t()
    var env = ProcessInfo.processInfo.environment
    env["MACSCOUT_CHILD"] = "1"
    var envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0)=\($1)") } + [nil]
    var argv: [UnsafeMutablePointer<CChar>?] = [strdup(runner), strdup(bundle), nil]
    let spawnError = posix_spawn(&pid, runner, nil, nil, &argv, &envp)
    argv.compactMap { $0 }.forEach { free($0) }
    envp.compactMap { $0 }.forEach { free($0) }
    guard spawnError == 0 else {
        print("MacscoutCoreTests: posix_spawn failed (\(spawnError))")
        return 1
    }
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 {}
    if (status & 0x7f) == 0 {
        return Int((status >> 8) & 0xff)
    }
    return 1
}
