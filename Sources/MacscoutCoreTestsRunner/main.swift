import Foundation

// Loads the MacscoutCoreTests bundle in a fresh process and runs the
// URLSession-based client tests. Spawned by the test bundle's bootstrap
// (Tests/MacscoutCoreTests/HarnessBootstrap.swift) because CFNetwork cannot
// initialize while the dyld lock is held inside a dlopen constructor.

guard CommandLine.arguments.count > 1 else {
    print("usage: MacscoutCoreTestsRunner <test-bundle-binary>")
    exit(2)
}
let bundlePath = CommandLine.arguments[1]
guard let handle = dlopen(bundlePath, RTLD_NOW) else {
    print("dlopen failed: \(String(cString: dlerror()))")
    exit(2)
}
typealias ClientSuite = @convention(c) () -> Int32
guard let symbol = dlsym(handle, "macscout_run_client_tests") else {
    print("macscout_run_client_tests not found in \(bundlePath)")
    exit(2)
}
let suite = unsafeBitCast(symbol, to: ClientSuite.self)
exit(suite())
