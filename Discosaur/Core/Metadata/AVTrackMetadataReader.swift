import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

nonisolated struct AVTrackMetadataReader: TrackMetadataReading {
    @concurrent
    func read(at url: URL) async throws -> TrackMetadata {
        try Task.checkCancellation()

        let asset = AVURLAsset(url: url)
        let commonItems = (try? await asset.load(.commonMetadata)) ?? []
        let title = try await text(for: [.commonIdentifierTitle], in: commonItems)
        let artist = try await text(for: [.commonIdentifierArtist], in: commonItems)
        let album = try await text(for: [.commonIdentifierAlbumName], in: commonItems)

        // Track/disc numbers and album artist are not part of common metadata.
        let items = (try? await asset.load(.metadata)) ?? []
        let albumArtist = try await text(
            for: [.iTunesMetadataAlbumArtist, .id3MetadataBand],
            in: items
        )
        let trackNumber = try await number(
            for: [.iTunesMetadataTrackNumber, .id3MetadataTrackNumber, .quickTimeUserDataTrack],
            in: items
        )
        let discNumber = try await number(
            for: [.iTunesMetadataDiscNumber, .id3MetadataPartOfASet],
            in: items
        )

        try Task.checkCancellation()
        // Core Audio may expose tags that AVFoundation's metadata omits.
        let needsFileTags = title == nil || artist == nil || album == nil
            || albumArtist == nil || trackNumber == nil || discNumber == nil
        let fileTags = needsFileTags ? readFileTags(at: url) : TrackMetadata()

        let assetDuration = (try? await asset.load(.duration))?.seconds
        var duration = TrackMetadata.validatedDuration(assetDuration)
        try Task.checkCancellation()
        if duration == nil {
            duration = readFileDuration(at: url)
        }

        try Task.checkCancellation()
        return TrackMetadata(
            title: title ?? fileTags.title,
            artist: artist ?? fileTags.artist,
            album: album ?? fileTags.album,
            albumArtist: albumArtist ?? fileTags.albumArtist,
            trackNumber: trackNumber ?? fileTags.trackNumber,
            discNumber: discNumber ?? fileTags.discNumber,
            duration: duration
        )
    }

    private func text(
        for identifiers: [AVMetadataIdentifier],
        in items: [AVMetadataItem]
    ) async throws -> String? {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                try Task.checkCancellation()
                guard let value = try? await item.load(.stringValue) else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func number(
        for identifiers: [AVMetadataIdentifier],
        in items: [AVMetadataItem]
    ) async throws -> Int? {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                try Task.checkCancellation()
                if let value = try? await item.load(.numberValue),
                   let number = TrackMetadata.sequenceNumber(from: value.stringValue) {
                    return number
                }
                if let value = try? await item.load(.stringValue),
                   let number = TrackMetadata.sequenceNumber(from: value) {
                    return number
                }

                // MP4's trkn/disk values can be binary: reserved UInt16,
                // number UInt16, total UInt16 (all big-endian), then padding.
                if identifier == .iTunesMetadataTrackNumber || identifier == .iTunesMetadataDiscNumber,
                   let data = try? await item.load(.dataValue), data.count >= 6 {
                    let bytes = Array(data)
                    let number = (Int(bytes[2]) << 8) | Int(bytes[3])
                    if number > 0 {
                        return number
                    }
                }
            }
        }
        return nil
    }

    private func readFileTags(at url: URL) -> TrackMetadata {
        var fileID: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr,
              let fileID else { return TrackMetadata() }
        defer { AudioFileClose(fileID) }

        // This property returns an owned CFDictionary, not borrowed storage.
        var dictionary: Unmanaged<CFDictionary>?
        var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        let result = AudioFileGetProperty(
            fileID,
            kAudioFilePropertyInfoDictionary,
            &size,
            &dictionary
        )
        guard result == noErr, let dictionary else { return TrackMetadata() }
        let tags = dictionary.takeRetainedValue() as NSDictionary

        return TrackMetadata(
            title: tag([kAFInfoDictionary_Title, "TITLE"], in: tags),
            artist: tag([kAFInfoDictionary_Artist, "ARTIST"], in: tags),
            album: tag([kAFInfoDictionary_Album, "ALBUM"], in: tags),
            albumArtist: tag(["album artist", "ALBUMARTIST", "ALBUM_ARTIST"], in: tags),
            trackNumber: TrackMetadata.sequenceNumber(
                from: tag([kAFInfoDictionary_TrackNumber, "TRACKNUMBER"], in: tags)
            ),
            discNumber: TrackMetadata.sequenceNumber(
                from: tag(["disc number", "DISCNUMBER"], in: tags)
            )
        )
    }

    private func tag(_ keys: [String], in tags: NSDictionary) -> String? {
        for key in keys {
            let value = (tags[key] as? String) ?? (tags[key] as? NSNumber)?.stringValue
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func readFileDuration(at url: URL) -> TimeInterval? {
        // Opening a file and inspecting its frame count does not read/decode its
        // PCM samples, and does not create or start a playback engine.
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        defer { file.close() }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate.isFinite, sampleRate > 0 else { return nil }
        return TrackMetadata.validatedDuration(Double(file.length) / sampleRate)
    }
}
