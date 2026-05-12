import AVFoundation
import Foundation

/// Composes alarm sound files: a user-selected source (bundled tone or recording)
/// followed by a silence tail, written to the App Group container so AlarmKit's
/// `AlertSound.named(...)` can resolve them at fire time.
///
/// Why this exists:
/// AlarmKit has no public API for "stop sounding after N seconds while keeping the
/// alarm scheduled." A long file with audible content for N seconds and silence
/// for the remainder gives us per-alarm duration control without needing a
/// paired silencer alarm.
///
/// Cache key strategy:
/// Files are keyed on `(sourceID, audibleDurationSec)`, NOT on alarm UUID. Multiple
/// alarms sharing the same melody+duration share one composed file on disk.
enum AlarmSoundComposer {
    static let appGroupID = "group.works.delicious.shabbatclock"

    /// Total length of every composed file. Long enough to outlast any plausible
    /// system audio cap; the silent tail compresses to almost nothing in AAC, so
    /// "extra" length costs negligible disk.
    static let totalDurationSeconds: Int = 30 * 60

    /// Fade-out applied to the final loop iteration of the audible portion.
    /// Smooths the transition into silence and avoids abrupt clipping when the
    /// audible duration falls mid-phrase in a looped melody.
    static let fadeOutSeconds: Double = 0.5

    /// Output encoding settings — mono 64 kbps AAC. Fine for alarm sounds; keeps
    /// composed files small.
    private static let outputBitRate: Int = 64_000
    private static let outputSampleRate: Double = 44_100

    /// Filename prefix that marks a file in `Library/Sounds/` as composer output
    /// rather than a user recording. Used by the orphan-prune walk to safely target
    /// only composer-owned files.
    static let composedFilePrefix = "composed_"

    // MARK: - Public API

    /// Composes a sound file for the given source + audible duration, writing to
    /// the App Group's `Library/Sounds/` directory (same dir AlarmKit resolves
    /// custom recordings from — validated via earlier spike). Returns the file's
    /// URL on success, nil on failure.
    ///
    /// Idempotent: if a file already exists for the cache key, returns it without
    /// recomposing. Synchronous; callers must NOT invoke from the main thread.
    static func compose(
        sourceURL: URL,
        audibleDurationSeconds: Int,
        cacheKey: String
    ) -> URL? {
        guard audibleDurationSeconds > 0 else {
            print("[AlarmSoundComposer] ❌ audibleDurationSeconds must be > 0, got \(audibleDurationSeconds)")
            return nil
        }
        guard let outURL = composedFileURL(for: cacheKey) else {
            print("[AlarmSoundComposer] ❌ could not resolve App Group container")
            return nil
        }
        if FileManager.default.fileExists(atPath: outURL.path) {
            return outURL
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("[AlarmSoundComposer] ❌ source file missing: \(sourceURL.path)")
            return nil
        }

        // Cap audible duration at total - 1s so there's always at least 1s of silent tail.
        let audibleSec = min(audibleDurationSeconds, totalDurationSeconds - 1)
        let totalSec = totalDurationSeconds

        do {
            try writeComposedFile(
                sourceURL: sourceURL,
                audibleDurationSeconds: Double(audibleSec),
                totalDurationSeconds: Double(totalSec),
                outputURL: outURL
            )
            return outURL
        } catch {
            print("[AlarmSoundComposer] ❌ composition failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
    }

    /// Delete the composed file for a cache key. No-op if missing.
    static func deleteComposed(cacheKey: String) {
        guard let url = composedFileURL(for: cacheKey) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Delete every composed file whose cache key isn't in `activeCacheKeys`.
    /// Call on app launch to clean up files left behind by deleted/edited alarms.
    /// Only walks composer-owned files (those with `composedFilePrefix`) — user
    /// recordings in the same directory are left untouched.
    ///
    /// Also removes the legacy `Library/ComposedSounds/` directory used by an
    /// earlier iteration; safe to drop entirely since AlarmKit can't read from
    /// that path anyway.
    static func pruneOrphans(activeCacheKeys: Set<String>) {
        // Sweep legacy directory if present.
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            let legacy = container
                .appendingPathComponent("Library")
                .appendingPathComponent("ComposedSounds")
            try? FileManager.default.removeItem(at: legacy)
        }

        guard let dir = composedSoundsDirectory() else { return }
        let activeFileNames = Set(activeCacheKeys.map { fileName(for: $0) })
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for name in contents where name.hasPrefix(composedFilePrefix) && !activeFileNames.contains(name) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// The string passed to `AlertConfiguration.AlertSound.named(...)` for a
    /// composed file. Bare filename — same convention as `CustomSoundStore`.
    static func alertSoundName(forCacheKey cacheKey: String) -> String {
        fileName(for: cacheKey)
    }

    // MARK: - Filesystem

    /// `Library/Sounds/` inside the App Group container — same directory used for
    /// user recordings. AlarmKit's `AlertSound.named(...)` resolves bare filenames
    /// from this exact path; subdirectories aren't walked. Created on demand.
    private static func composedSoundsDirectory() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return nil
        }
        let dir = container
            .appendingPathComponent("Library")
            .appendingPathComponent("Sounds")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }
        return dir
    }

    private static func fileName(for cacheKey: String) -> String {
        let sanitized = cacheKey
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return "\(composedFilePrefix)\(sanitized).m4a"
    }

    private static func composedFileURL(for cacheKey: String) -> URL? {
        composedSoundsDirectory()?.appendingPathComponent(fileName(for: cacheKey))
    }

    // MARK: - Composition

    private enum ComposeError: Error {
        case cannotCreateAsset
        case cannotCreateReader
        case cannotCreateWriter
        case noAudioTrack
        case readerFailed(String)
        case writerFailed(String)
    }

    /// Writes a composed file: source audio for `audibleDurationSeconds`
    /// (looping if shorter than the duration, with a fade-out on the final
    /// loop iteration), followed by silence to reach `totalDurationSeconds`.
    ///
    /// The whole pipeline runs on PCM frames (44.1 kHz mono Float32) and is
    /// re-encoded to AAC by `AVAssetWriter`. Synchronous — composition takes
    /// ~100-300 ms for typical inputs.
    private static func writeComposedFile(
        sourceURL: URL,
        audibleDurationSeconds: Double,
        totalDurationSeconds: Double,
        outputURL: URL
    ) throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw ComposeError.noAudioTrack
        }

        let pcmFormat: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: outputSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        // 1. Decode source to PCM frames (mono float32, 44.1 kHz).
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: pcmFormat)
        guard reader.canAdd(readerOutput) else { throw ComposeError.cannotCreateReader }
        reader.add(readerOutput)
        guard reader.startReading() else {
            throw ComposeError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }

        var sourceFrames: [Float] = []
        sourceFrames.reserveCapacity(Int(outputSampleRate * 60)) // typical alarm sound is short
        while let buf = readerOutput.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buf) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            )
            guard let p = dataPointer else { continue }
            let count = length / MemoryLayout<Float>.size
            p.withMemoryRebound(to: Float.self, capacity: count) { floatPtr in
                sourceFrames.append(contentsOf: UnsafeBufferPointer(start: floatPtr, count: count))
            }
        }
        if reader.status == .failed {
            throw ComposeError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        guard !sourceFrames.isEmpty else {
            throw ComposeError.readerFailed("source produced 0 frames")
        }

        let totalAudibleFrames = Int(audibleDurationSeconds * outputSampleRate)
        let totalFinalFrames = Int(totalDurationSeconds * outputSampleRate)
        let fadeFrames = min(Int(fadeOutSeconds * outputSampleRate), totalAudibleFrames)

        // 2. Build the audible portion: loop source until we reach `totalAudibleFrames`,
        //    then apply a fade-out across the final `fadeFrames` samples.
        var audible: [Float] = []
        audible.reserveCapacity(totalAudibleFrames)
        var idx = 0
        while audible.count < totalAudibleFrames {
            audible.append(sourceFrames[idx % sourceFrames.count])
            idx += 1
        }
        if fadeFrames > 0 {
            let fadeStart = totalAudibleFrames - fadeFrames
            for i in 0..<fadeFrames {
                let gain = 1.0 - Float(i) / Float(fadeFrames)
                audible[fadeStart + i] *= gain
            }
        }

        // 3. Set up the writer.
        let writerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: outputSampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: outputBitRate
        ]
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw ComposeError.cannotCreateWriter }
        writer.add(writerInput)
        guard writer.startWriting() else {
            throw ComposeError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        // 4. Write audible chunk + silent chunk in fixed-size blocks. Mixing them
        //    in the same loop with a single PCM format description keeps the
        //    timing math simple.
        let chunkFrames = 4096
        var written = 0
        let asbdMaker = monoFloat32ASBD()
        var asbd = asbdMaker
        var formatDescription: CMAudioFormatDescription?
        let fdStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard fdStatus == noErr, let fd = formatDescription else {
            throw ComposeError.writerFailed("CMAudioFormatDescriptionCreate failed: \(fdStatus)")
        }

        var pendingError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "AlarmSoundComposer.writer")

        writerInput.requestMediaDataWhenReady(on: queue) {
            while writerInput.isReadyForMoreMediaData {
                if written >= totalFinalFrames {
                    writerInput.markAsFinished()
                    semaphore.signal()
                    return
                }
                let frames = min(chunkFrames, totalFinalFrames - written)
                var buffer = [Float](repeating: 0, count: frames)
                if written < totalAudibleFrames {
                    let take = min(frames, totalAudibleFrames - written)
                    buffer.withUnsafeMutableBufferPointer { dst in
                        audible.withUnsafeBufferPointer { src in
                            for i in 0..<take {
                                dst[i] = src[written + i]
                            }
                        }
                    }
                    // Frames beyond `take` (if we crossed the audible/silence boundary
                    // mid-chunk) stay zero from the initial `repeating: 0`.
                }
                do {
                    let sample = try makeSampleBuffer(
                        floats: buffer,
                        startFrame: written,
                        formatDescription: fd
                    )
                    if !writerInput.append(sample) {
                        pendingError = ComposeError.writerFailed(
                            writer.error?.localizedDescription ?? "append failed"
                        )
                        writerInput.markAsFinished()
                        semaphore.signal()
                        return
                    }
                    written += frames
                } catch {
                    pendingError = error
                    writerInput.markAsFinished()
                    semaphore.signal()
                    return
                }
            }
        }

        semaphore.wait()
        if let err = pendingError {
            writer.cancelWriting()
            throw err
        }

        let finishSemaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { finishSemaphore.signal() }
        finishSemaphore.wait()

        if writer.status != .completed {
            throw ComposeError.writerFailed(writer.error?.localizedDescription ?? "writer status \(writer.status.rawValue)")
        }
    }

    // MARK: - Audio plumbing

    private static func monoFloat32ASBD() -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: outputSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    private static func makeSampleBuffer(
        floats: [Float],
        startFrame: Int,
        formatDescription: CMAudioFormatDescription
    ) throws -> CMSampleBuffer {
        let byteCount = floats.count * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        let allocStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard allocStatus == noErr, let block = blockBuffer else {
            throw ComposeError.writerFailed("CMBlockBufferCreate failed: \(allocStatus)")
        }
        let copyStatus = floats.withUnsafeBufferPointer { src -> OSStatus in
            CMBlockBufferReplaceDataBytes(
                with: src.baseAddress!,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard copyStatus == noErr else {
            throw ComposeError.writerFailed("CMBlockBufferReplaceDataBytes failed: \(copyStatus)")
        }

        let presentationTime = CMTime(
            value: CMTimeValue(startFrame),
            timescale: CMTimeScale(outputSampleRate)
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(floats.count),
            presentationTimeStamp: presentationTime,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let buffer = sampleBuffer else {
            throw ComposeError.writerFailed("CMSampleBufferCreate failed: \(sampleStatus)")
        }
        return buffer
    }
}
