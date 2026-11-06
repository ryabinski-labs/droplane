import Foundation

/// Small mutation fuzzer for the exported `LLVMFuzzerTestOneInput` harness.
/// macOS Swift does not ship libFuzzer's `-sanitize=fuzzer`, so this runner
/// supplies the loop and the corpus while the harness stays compatible with
/// libFuzzer/OSS-Fuzz on platforms that do.
@main
struct FuzzRunner {
    static func main() {
        let seconds = max(1, Int(CommandLine.arguments.dropFirst().first ?? "60") ?? 60)
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        let seeds: [[UInt8]] = [
            [0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x04, 0x38, 0x07, 0x80, 0x03, 0x01, 0x11, 0x00, 0xFF, 0xD9],
            Array("PrimeCam_20261030_1421.mov".utf8),
            Array("../../etc/passwd".utf8),
            Array("notes: draft.txt".utf8),
            Array(repeating: 0xFF, count: 64),
            [],
        ]
        var generator = SystemRandomNumberGenerator()
        var iterations = 0

        while Date() < deadline {
            var input = seeds.randomElement(using: &generator) ?? []
            let mutations = Int.random(in: 1...8, using: &generator)
            for _ in 0..<mutations {
                switch Int.random(in: 0...4, using: &generator) {
                case 0 where !input.isEmpty:
                    input[Int.random(in: 0..<input.count, using: &generator)] ^= UInt8.random(in: 0...255, using: &generator)
                case 1:
                    input.insert(UInt8.random(in: 0...255, using: &generator), at: Int.random(in: 0...input.count, using: &generator))
                case 2 where !input.isEmpty:
                    input.remove(at: Int.random(in: 0..<input.count, using: &generator))
                case 3:
                    let count = Int.random(in: 1...256, using: &generator)
                    input.append(contentsOf: (0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
                default:
                    if input.count > 2 {
                        input = Array(input.prefix(Int.random(in: 1..<input.count, using: &generator)))
                    }
                }
                if input.count > 65_536 { input = Array(input.prefix(65_536)) }
            }

            input.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                _ = droplaneFuzzOneInput(base, buffer.count)
            }
            iterations += 1
        }
        print("Fuzzed \(iterations) inputs in \(seconds)s")
    }
}
