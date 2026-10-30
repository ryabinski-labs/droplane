// Generated from tdd/android-file-copier.tdd.yaml. Red phase: each test fails on purpose
// and is wrapped in a strict expected failure, so it turns into a failure once the scenario
// passes. Delete the XCTExpectFailure wrapper as each scenario goes green.
import XCTest
@testable import TransferCore

final class TransferCoreTests: XCTestCase {
    /// SC-001-a [unit] Fake device connect lists storages
    /// Given a FakeMTPDevice with 2 storages and 3 root folders; when DeviceMonitor reports it attached; then the phone pane model lists 2 storages and 3 folders
    func test_SC_001_a() {
        XCTExpectFailure("RED SC-001-a: not implemented", options: .init()) {
            XCTFail("Oracle: pane.storages.count == 2 AND pane.rootFolders.count == 3")
        }
    }

    /// SC-001-b [contract] libmtp wrapper conforms to MTPDevice protocol on real hardware
    /// Given the maintainer's physical phone is unlocked in File transfer mode; when the real LibMTPDevice connects; then storages and root folders are listed within 5 seconds
    func test_SC_001_b() {
        XCTExpectFailure("RED SC-001-b: not implemented", options: .init()) {
            XCTFail("Oracle: elapsed_ms(connect..listRoot) <= 5000 AND storages.count >= 1")
        }
    }

    /// SC-001-c [unit] Locked or charge-only phone shows unlock guidance
    /// Given a device whose open call fails with no-device-in-MTP-mode; when DeviceMonitor handles the failure; then state is .needsUnlock with the exact guidance text and a Refresh action
    func test_SC_001_c() {
        XCTExpectFailure("RED SC-001-c: not implemented", options: .init()) {
            XCTFail("Oracle: state == .needsUnlock AND message == 'Unlock your phone and choose File transfer (MTP) in the USB notification'")
        }
    }

    /// SC-001-d [unit] Busy interface shows quit-other-apps guidance
    /// Given a device whose open call fails with the interface-claimed error; when DeviceMonitor handles the failure; then state is .busy with the exact text
    func test_SC_001_d() {
        XCTExpectFailure("RED SC-001-d: not implemented", options: .init()) {
            XCTFail("Oracle: message == 'Another app is using your phone. Quit Android File Transfer, Samsung Smart Switch, or any other phone manager, then press Refresh'")
        }
    }

    /// SC-002-a [integration] Single file copies byte-identical
    /// Given a fake phone file of 10 MiB random bytes and an empty Mac temp folder; when the queue copies it to the Mac; then the queue row is Done and the Mac file has the same SHA-256
    func test_SC_002_a() {
        XCTExpectFailure("RED SC-002-a: not implemented", options: .init()) {
            XCTFail("Oracle: sha256(mac_file) == sha256(source_bytes) AND row.state == .done")
        }
    }

    /// SC-002-b [integration] File over 4 GiB streams without 32-bit truncation
    /// Given a fake phone file of 4 GiB + 1 byte produced by a deterministic generator; when the queue copies it to the Mac; then the Mac file size is 4294967297 and the SHA-256 matches the generator's digest
    func test_SC_002_b() {
        XCTExpectFailure("RED SC-002-b: not implemented", options: .init()) {
            XCTFail("Oracle: mac_file.size == 4294967297 AND sha256 matches")
        }
    }

    /// SC-002-c [integration] Folder subtree is preserved
    /// Given a fake phone folder with 3 nested levels and 7 files; when the folder is copied to a Mac folder; then the Mac tree has identical relative paths and file hashes
    func test_SC_002_c() {
        XCTExpectFailure("RED SC-002-c: not implemented", options: .init()) {
            XCTFail("Oracle: relativePaths(mac) == relativePaths(phone) AND hashes equal")
        }
    }

    /// SC-002-d [unit] Progress reports percent and MB/s
    /// Given a transfer of 100 MB where 25 MB moved in 1 second; when the progress model updates; then row shows 25 percent and 25.0 MB/s
    func test_SC_002_d() {
        XCTExpectFailure("RED SC-002-d: not implemented", options: .init()) {
            XCTFail("Oracle: row.percent == 25 AND row.mbPerSecond == 25.0")
        }
    }

    /// SC-002-e [unit] Insufficient Mac space blocks the copy
    /// Given a queue needing 5 GB and a Mac volume reporting 2 GB free; when the user starts the copy; then nothing is transferred and the message names both sizes
    func test_SC_002_e() {
        XCTExpectFailure("RED SC-002-e: not implemented", options: .init()) {
            XCTFail("Oracle: bytesTransferred == 0 AND message == 'Not enough space on the Mac: needs 5.0 GB, has 2.0 GB'")
        }
    }

    /// SC-003-a [unit] Keep Both names the copy 'name 2.ext'
    /// Given a destination already containing clip.mp4; when ConflictResolver resolves clip.mp4 with Keep Both; then the new name is 'clip 2.mp4' and a second clash yields 'clip 3.mp4'
    func test_SC_003_a() {
        XCTExpectFailure("RED SC-003-a: not implemented", options: .init()) {
            XCTFail("Oracle: names == ['clip 2.mp4','clip 3.mp4']")
        }
    }

    /// SC-003-b [integration] Existing file untouched until the user decides
    /// Given a Mac file clip.mp4 with known hash H and a phone file clip.mp4 with different bytes; when the queue reaches the clash; then the queue pauses with a pending decision and the Mac file hash is still H
    func test_SC_003_b() {
        XCTExpectFailure("RED SC-003-b: not implemented", options: .init()) {
            XCTFail("Oracle: queue.state == .awaitingDecision AND sha256(mac_clip) == H")
        }
    }

    /// SC-003-c [integration] Skip with Apply to All skips every later clash
    /// Given 3 clashing files and the user picks Skip with Apply to All on the first; when the queue finishes; then all 3 are skipped, no prompt appears twice, Mac hashes are unchanged
    func test_SC_003_c() {
        XCTExpectFailure("RED SC-003-c: not implemented", options: .init()) {
            XCTFail("Oracle: prompts == 1 AND skipped == 3 AND hashes unchanged")
        }
    }

    /// SC-004-a [integration] Cancel deletes the partial Mac file
    /// Given a running 1 GiB copy at 40 percent; when the user cancels the queue row; then the transfer stops within 2 seconds and no partial file remains
    func test_SC_004_a() {
        XCTExpectFailure("RED SC-004-a: not implemented", options: .init()) {
            XCTFail("Oracle: elapsed_ms <= 2000 AND NOT exists(mac_partial)")
        }
    }

    /// SC-004-b [integration] Unplug mid-copy fails every unfinished row
    /// Given a queue of 3 files with the first at 50 percent; when the fake device reports disconnected; then unfinished rows read Failed with 'Phone disconnected', no partial files remain, Retry is offered
    func test_SC_004_b() {
        XCTExpectFailure("RED SC-004-b: not implemented", options: .init()) {
            XCTFail("Oracle: all unfinished rows == .failed('Phone disconnected') AND no partial files AND row.canRetry")
        }
    }

    /// SC-004-c [integration] Retry re-queues failed rows after reconnect
    /// Given failed rows from SC-004-b and the device reattached; when the user presses Retry; then rows complete with matching hashes
    func test_SC_004_c() {
        XCTExpectFailure("RED SC-004-c: not implemented", options: .init()) {
            XCTFail("Oracle: rows == .done AND hashes equal")
        }
    }

    /// SC-005-a [acceptance] Release DMG passes Gatekeeper assessment
    /// Given a DMG built by the release script on a Mac with the Developer ID cert (R-001); when scripts/release.sh --verify runs spctl and stapler; then the app is accepted as Notarized Developer ID and the DMG is stapled
    func test_SC_005_a() {
        XCTExpectFailure("RED SC-005-a: not implemented", options: .init()) {
            XCTFail("Oracle: spctl --assess --type execute exits 0 with 'source=Notarized Developer ID' AND stapler validate exits 0")
        }
    }

    /// SC-005-b [integration] Binary is universal with minimum macOS 14
    /// Given the built app bundle; when lipo and plutil inspect it; then arm64 and x86_64 slices exist and LSMinimumSystemVersion is 14.0
    func test_SC_005_b() {
        XCTExpectFailure("RED SC-005-b: not implemented", options: .init()) {
            XCTFail("Oracle: lipo -archs includes 'arm64' and 'x86_64' AND LSMinimumSystemVersion == '14.0'")
        }
    }

    /// SC-005-c [integration] Hardened runtime and libmtp bundled dynamically
    /// Given the built app bundle; when codesign -dv and otool -L inspect it; then hardened runtime flag is set and libmtp is a dylib inside Frameworks
    func test_SC_005_c() {
        XCTExpectFailure("RED SC-005-c: not implemented", options: .init()) {
            XCTFail("Oracle: codesign flags contains 'runtime' AND otool -L lists @rpath/libmtp dylib")
        }
    }

    /// SC-006-a [acceptance] Demo Device appears and lists sample files
    /// Given the app launched with the Device menu Demo Device item enabled; when the user selects Demo Device; then the phone pane lists the sample folders and files
    func test_SC_006_a() {
        XCTExpectFailure("RED SC-006-a: not implemented", options: .init()) {
            XCTFail("Oracle: XCUITest: phone pane row count == sampleTree.rootCount")
        }
    }

    /// SC-006-b [integration] No remote and no push in scripts
    /// Given the repository at the first commit; when scripts and git config are scanned; then no remote exists and no script contains 'git push'
    func test_SC_006_b() {
        XCTExpectFailure("RED SC-006-b: not implemented", options: .init()) {
            XCTFail("Oracle: git remote | wc -l == 0 AND grep -r 'git push' scripts == empty")
        }
    }

    /// SC-007-a [integration] Mac file lands on phone with equal size and hash
    /// Given a 10 MiB Mac file and a fake phone folder; when the queue copies it to the phone; then the fake device holds the same bytes
    func test_SC_007_a() {
        XCTExpectFailure("RED SC-007-a: not implemented", options: .init()) {
            XCTFail("Oracle: fake.read(path) sha256 == sha256(mac_file)")
        }
    }

    /// SC-007-b [integration] Full phone fails with exact message
    /// Given a fake storage with 1 MB free and a 10 MB Mac file; when the queue copies it; then the row is Failed with the exact text and no partial object remains
    func test_SC_007_b() {
        XCTExpectFailure("RED SC-007-b: not implemented", options: .init()) {
            XCTFail("Oracle: row.state == .failed('Not enough space on the phone') AND NOT fake.exists(path)")
        }
    }

    /// SC-008-a [integration] Rename changes the name on the device
    /// Given a fake phone file a.txt; when rename to b.txt; then the device lists b.txt and not a.txt
    func test_SC_008_a() {
        XCTExpectFailure("RED SC-008-a: not implemented", options: .init()) {
            XCTFail("Oracle: fake.list contains 'b.txt' AND NOT contains 'a.txt'")
        }
    }

    /// SC-008-b [unit] Delete requires confirmation
    /// Given 2 selected phone items; when delete is requested and confirmation is cancelled; then nothing is deleted and the prompt text matches
    func test_SC_008_b() {
        XCTExpectFailure("RED SC-008-b: not implemented", options: .init()) {
            XCTFail("Oracle: fake.deleteCalls == 0 AND prompt == 'Delete 2 items from your phone? This cannot be undone'")
        }
    }

    /// SC-008-c [integration] New folder creates a folder
    /// Given a fake phone folder open; when new folder 'Clips' is created; then the folder exists on the device
    func test_SC_008_c() {
        XCTExpectFailure("RED SC-008-c: not implemented", options: .init()) {
            XCTFail("Oracle: fake.exists('/DCIM/Clips') == true")
        }
    }

    /// SC-009-a [unit] Dot-files hidden by default
    /// Given a listing containing '.thumbnails' and 'a.mp4'; when the default pane filter applies; then only a.mp4 is shown
    func test_SC_009_a() {
        XCTExpectFailure("RED SC-009-a: not implemented", options: .init()) {
            XCTFail("Oracle: visible == ['a.mp4']")
        }
    }

    /// SC-009-b [unit] View mode persists across relaunch
    /// Given left pane set to icon view in an isolated UserDefaults suite; when a new PreferencesStore reads the suite; then left pane is icon view
    func test_SC_009_b() {
        XCTExpectFailure("RED SC-009-b: not implemented", options: .init()) {
            XCTFail("Oracle: store.viewMode(.left) == .icon")
        }
    }

    /// SC-010-a [contract] Appcast entry carries a valid EdDSA signature
    /// Given a generated appcast for version 0.1.1; when sign_update verification runs against the public key in Info.plist; then verification succeeds
    func test_SC_010_a() {
        XCTExpectFailure("RED SC-010-a: not implemented", options: .init()) {
            XCTFail("Oracle: sparkle verify exits 0")
        }
    }

    /// SC-011-a [unit] Colon is sanitized
    /// Given a phone file named 'a:b.mp4'; when the Mac destination name is derived; then the name is 'a_b.mp4' and the row notes the change
    func test_SC_011_a() {
        XCTExpectFailure("RED SC-011-a: not implemented", options: .init()) {
            XCTFail("Oracle: name == 'a_b.mp4' AND row.note != nil")
        }
    }

    /// SC-012-a [integration] Listing 1,000 entries meets 2 s
    /// Given a fake folder with 1000 entries; when the pane lists it; then rows render in at most 2 seconds
    func test_SC_012_a() {
        XCTExpectFailure("RED SC-012-a: not implemented", options: .init()) {
            XCTFail("Oracle: elapsed_ms <= 2000")
        }
    }

}
