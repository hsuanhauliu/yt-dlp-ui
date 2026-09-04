import Testing
import Foundation
@testable import YtDlpUI

struct ProgressParserTests {

    private func progressLine(_ fields: String) -> String {
        "\(ArgBuilder.progressSentinel)\t\(fields)"
    }

    @Test func parsesFullProgress() {
        let line = progressLine("524288\t1048576\t1048576\t131072.0\t4")
        guard case .progress(let p)? = ProgressParser.parse(line) else {
            Issue.record("expected .progress"); return
        }
        #expect(p.downloadedBytes == 524_288)
        #expect(p.totalBytes == 1_048_576)
        #expect(p.speedBytesPerSecond == 131_072)
        #expect(p.etaSeconds == 4)
        #expect(p.fraction == 0.5)
    }

    @Test func handlesNAFields() {
        let line = progressLine("1024\tNA\tNA\tNA\tNA")
        guard case .progress(let p)? = ProgressParser.parse(line) else {
            Issue.record("expected .progress"); return
        }
        #expect(p.downloadedBytes == 1024)
        #expect(p.totalBytes == nil)
        #expect(p.speedBytesPerSecond == nil)
        #expect(p.fraction == nil)
    }

    @Test func fallsBackToEstimateForTotal() {
        let line = progressLine("500\tNA\t1000\tNA\tNA")
        guard case .progress(let p)? = ProgressParser.parse(line) else {
            Issue.record("expected .progress"); return
        }
        #expect(p.totalBytes == 1000)
        #expect(p.fraction == 0.5)
    }

    @Test func parsesTitle() {
        let line = "\(ArgBuilder.titleSentinel) Never Gonna Give You Up"
        #expect(ProgressParser.parse(line) == .title("Never Gonna Give You Up"))
    }

    @Test func parsesOutputPath() {
        let line = "\(ArgBuilder.pathSentinel) /Users/me/Downloads/video.mp4"
        #expect(ProgressParser.parse(line) == .outputPath(URL(fileURLWithPath: "/Users/me/Downloads/video.mp4")))
    }

    @Test func detectsPostProcessing() {
        #expect(ProgressParser.parse(#"[Merger] Merging formats into "video.mp4""#) == .postProcessing)
        #expect(ProgressParser.parse("[ExtractAudio] Destination: song.mp3") == .postProcessing)
        #expect(ProgressParser.parse("[EmbedThumbnail] Adding thumbnail to \"video.mp4\"") == .postProcessing)
    }

    @Test func detectsAlreadyDownloaded() {
        let line = "[download] video.mp4 has already been downloaded"
        #expect(ProgressParser.parse(line) == .alreadyDownloaded)
    }

    @Test func ignoresChatter() {
        #expect(ProgressParser.parse("[youtube] abc123: Downloading webpage") == nil)
        #expect(ProgressParser.parse("") == nil)
        #expect(ProgressParser.parse("[info] abc123: Downloading 1 format(s): 22") == nil)
    }
}
