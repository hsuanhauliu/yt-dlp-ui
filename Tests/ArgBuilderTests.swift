import Testing
import Foundation
@testable import YtDlpUI

struct ArgBuilderTests {

    private func makeArgs(_ selection: FormatSelection) -> [String] {
        ArgBuilder.build(
            DownloadRequest(
                url: "https://example.com/watch?v=abc123",
                selection: selection,
                destinationDirectory: URL(fileURLWithPath: "/tmp/dl")
            ),
            toolsDirectory: URL(fileURLWithPath: "/opt/tools/bin"),
            cacheDirectory: URL(fileURLWithPath: "/opt/cache"),
            outputDirectory: URL(fileURLWithPath: "/opt/staging/job1")
        )
    }

    @Test func alwaysHermetic() {
        let cases: [FormatSelection] = [
            FormatSelection(),
            FormatSelection(kind: .audio),
            FormatSelection(kind: .video, videoQuality: .p720, videoContainer: .mkv),
        ]
        for selection in cases {
            let args = makeArgs(selection)
            #expect(args.contains("--ignore-config"))
            #expect(args.contains("--newline"))
            #expect(args.contains("--no-simulate"))
            #expect(args.contains("--progress"))
            #expect(consecutive(args, "--ffmpeg-location", "/opt/tools/bin"))
            #expect(consecutive(args, "--cache-dir", "/opt/cache"))
            #expect(args.contains("home:/opt/staging/job1"))   // staging dir, not the final destination
            #expect(args.last == "https://example.com/watch?v=abc123")
        }
    }

    @Test func videoBestMergesToMp4() {
        let args = makeArgs(FormatSelection(kind: .video, videoQuality: .best, videoContainer: .mp4))
        #expect(consecutive(args, "-f", "bv*+ba/b"))
        #expect(consecutive(args, "--merge-output-format", "mp4"))
        #expect(consecutive(args, "--remux-video", "mp4"))
    }

    @Test func videoQualityCapsHeight() {
        let args = makeArgs(FormatSelection(kind: .video, videoQuality: .p1080))
        #expect(args.contains { $0.contains("height<=1080") })
    }

    @Test func videoContainerMkv() {
        let args = makeArgs(FormatSelection(kind: .video, videoContainer: .mkv))
        #expect(consecutive(args, "--merge-output-format", "mkv"))
        #expect(!args.contains("mp4"))
    }

    @Test func videoContainerAutoDoesNotForce() {
        let args = makeArgs(FormatSelection(kind: .video, videoContainer: .auto))
        #expect(!args.contains("--merge-output-format"))
        #expect(!args.contains("--remux-video"))
    }

    @Test func audioMp3() {
        let args = makeArgs(FormatSelection(kind: .audio, audioFormat: .mp3))
        #expect(args.contains("-x"))
        #expect(consecutive(args, "--audio-format", "mp3"))
        #expect(!args.contains("--merge-output-format"))
        #expect(!args.contains("-f"))
    }

    @Test func audioOpus() {
        let args = makeArgs(FormatSelection(kind: .audio, audioFormat: .opus))
        #expect(consecutive(args, "--audio-format", "opus"))
    }

    @Test func progressTemplateCarriesSentinel() {
        let args = makeArgs(FormatSelection())
        guard let i = args.firstIndex(of: "--progress-template") else {
            Issue.record("no --progress-template"); return
        }
        #expect(args[i + 1].hasPrefix("download:\(ArgBuilder.progressSentinel)"))
    }

    @Test func selectionSummary() {
        #expect(FormatSelection(kind: .video, videoQuality: .p1080, videoContainer: .mp4).summary == "1080p · MP4")
        #expect(FormatSelection(kind: .audio, audioFormat: .m4a).summary == "M4A")
    }

    @Test func updateArguments() {
        #expect(ToolManager.updateArguments(target: "stable") == ["--update-to", "stable", "--ignore-config", "--no-colors"])
        #expect(ToolManager.updateArguments(target: "nightly").contains("nightly"))
    }

    private func consecutive(_ args: [String], _ a: String, _ b: String) -> Bool {
        for i in args.indices.dropLast() where args[i] == a && args[i + 1] == b {
            return true
        }
        return false
    }
}
