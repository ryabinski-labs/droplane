import Foundation

/// libFuzzer entry point for the parsers that read untrusted phone data.
/// A phone supplies both filenames and thumbnail bytes, so neither is trusted.
/// Build and run with `./scripts/fuzz.sh`.
@_cdecl("LLVMFuzzerTestOneInput")
public func droplaneFuzzOneInput(_ bytes: UnsafePointer<UInt8>, _ size: Int) -> Int32 {
    let data = Data(bytes: bytes, count: size)
    _ = JPEGDimensions.size(in: data)
    _ = MediaClassifier.kind(of: String(decoding: data, as: UTF8.self))
    let name = String(decoding: data, as: UTF8.self)
    _ = NameSanitizer.forMac(name)
    _ = NameSanitizer.forPhone(name)
    return 0
}
