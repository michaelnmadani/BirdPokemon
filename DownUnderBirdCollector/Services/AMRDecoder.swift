import Foundation
import AMRNB
import AMRWB

/// Voice-recorder audio (AMR-NB / AMR-WB), which iOS can't decode: a raw
/// `.amr` file or the AMR track of a `.3gp`/`.3ga`, as many Android recorders
/// save. Mirrors `amrKind` / `amrFrom3gp` in `web/src/js/soundid-core.js`;
/// decoding uses opencore-amr (ThirdParty/OpenCoreAMR).
enum AMRDecoder {
    enum Kind { case narrowband, wideband }

    enum DecodeError: LocalizedError {
        case noAudio
        var errorDescription: String? { "The AMR recording has no audio in it." }
    }

    private static let nbMagic = Data("#!AMR\n".utf8)
    private static let wbMagic = Data("#!AMR-WB\n".utf8)

    /// Payload bytes after each frame's TOC byte, by frame type (opencore's
    /// tables); nil marks types that can't appear in a file.
    private static let nbPayload: [Int?] = [12, 13, 15, 17, 19, 20, 26, 31, 5, 6, 5, 5, 0, 0, 0, 0]
    private static let wbPayload: [Int?] = [17, 23, 32, 36, 40, 46, 50, 58, 60, 5, nil, nil, nil, nil, 0, 0]

    static func kind(of data: Data) -> Kind? {
        if data.starts(with: wbMagic) { return .wideband }
        if data.starts(with: nbMagic) { return .narrowband }
        return nil
    }

    /// The file as a raw .amr: itself if it already is one, or the AMR track
    /// pulled out of a 3GP/MP4 container. nil if it isn't AMR at all.
    static func amrFile(from data: Data) -> Data? {
        if kind(of: data) != nil { return data }
        return amrFrom3GP(data)
    }

    /// Decodes a raw .amr file to mono samples at 8 kHz (NB) or 16 kHz (WB).
    static func decode(_ file: Data) throws -> (samples: [Float], sampleRate: Double) {
        guard let kind = kind(of: file) else { throw DecodeError.noAudio }
        let bytes = [UInt8](file)
        let wide = kind == .wideband
        var offset = wide ? wbMagic.count : nbMagic.count
        let frameSamples = wide ? 320 : 160
        let state = wide ? D_IF_init() : Decoder_Interface_init()
        defer { wide ? D_IF_exit(state) : Decoder_Interface_exit(state) }

        var samples: [Float] = []
        samples.reserveCapacity((bytes.count / 20) * frameSamples)
        var pcm = [Int16](repeating: 0, count: frameSamples)
        while offset < bytes.count {
            guard let payload = (wide ? wbPayload : nbPayload)[Int(bytes[offset] >> 3) & 0x0F],
                  offset + 1 + payload <= bytes.count else { break }
            bytes.withUnsafeBufferPointer { frame in
                pcm.withUnsafeMutableBufferPointer { out in
                    let input = frame.baseAddress! + offset
                    if wide {
                        D_IF_decode(state, input, out.baseAddress, 0)
                    } else {
                        Decoder_Interface_Decode(state, input, out.baseAddress, 0)
                    }
                }
            }
            samples.append(contentsOf: pcm.lazy.map { Float($0) / 32_768 })
            offset += 1 + payload
        }
        guard !samples.isEmpty else { throw DecodeError.noAudio }
        return (samples, wide ? 16_000 : 8_000)
    }

    // MARK: - 3GP / MP4 container

    private struct Box {
        let type: String
        let start: Int   // payload start
        let end: Int
    }

    private static func boxes(_ b: [UInt8], _ start: Int, _ end: Int) -> [Box] {
        var out: [Box] = []
        var pos = start
        while pos + 8 <= end {
            var size = Int(u32(b, pos))
            let type = String(decoding: b[(pos + 4)..<(pos + 8)], as: UTF8.self)
            var header = 8
            if size == 1 {
                guard pos + 16 <= end else { break }
                size = Int(u64(b, pos + 8))
                header = 16
            } else if size == 0 {
                size = end - pos
            }
            guard size >= header, pos + size <= end else { break }
            out.append(Box(type: type, start: pos + header, end: pos + size))
            pos += size
        }
        return out
    }

    private static func child(_ b: [UInt8], _ box: Box, _ type: String) -> Box? {
        boxes(b, box.start, box.end).first { $0.type == type }
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
    }

    private static func u64(_ b: [UInt8], _ i: Int) -> UInt64 {
        UInt64(u32(b, i)) << 32 | UInt64(u32(b, i + 4))
    }

    /// The AMR track of a 3GP/3GA file as a raw .amr file, or nil if there isn't one.
    static func amrFrom3GP(_ data: Data) -> Data? {
        let b = [UInt8](data)
        guard let moov = boxes(b, 0, b.count).first(where: { $0.type == "moov" }) else { return nil }
        for trak in boxes(b, moov.start, moov.end) where trak.type == "trak" {
            guard let mdia = child(b, trak, "mdia"), let minf = child(b, mdia, "minf"),
                  let stbl = child(b, minf, "stbl"), let stsd = child(b, stbl, "stsd"),
                  stsd.start + 8 <= stsd.end,
                  let entry = boxes(b, stsd.start + 8, stsd.end).first,   // skip version/flags + count
                  entry.type == "samr" || entry.type == "sawb" else { continue }
            guard let stsz = child(b, stbl, "stsz"), let stsc = child(b, stbl, "stsc"),
                  let stco = child(b, stbl, "stco") ?? child(b, stbl, "co64"),
                  stsz.start + 12 <= stsz.end, stsc.start + 8 <= stsc.end, stco.start + 8 <= stco.end
            else { return nil }

            let fixedSize = Int(u32(b, stsz.start + 4))
            let sampleCount = Int(u32(b, stsz.start + 8))
            guard fixedSize > 0 || stsz.start + 12 + sampleCount * 4 <= stsz.end else { return nil }
            let sizes = (0..<sampleCount).map { fixedSize > 0 ? fixedSize : Int(u32(b, stsz.start + 12 + $0 * 4)) }

            let is64 = stco.type == "co64"
            let chunkCount = Int(u32(b, stco.start + 4))
            guard stco.start + 8 + chunkCount * (is64 ? 8 : 4) <= stco.end else { return nil }
            let chunkOffsets = (0..<chunkCount).map {
                is64 ? Int(u64(b, stco.start + 8 + $0 * 8)) : Int(u32(b, stco.start + 8 + $0 * 4))
            }

            let runCount = Int(u32(b, stsc.start + 4))
            guard stsc.start + 8 + runCount * 12 <= stsc.end else { return nil }
            let runs = (0..<runCount).map {
                (firstChunk: Int(u32(b, stsc.start + 8 + $0 * 12)), samplesPerChunk: Int(u32(b, stsc.start + 12 + $0 * 12)))
            }

            var out = entry.type == "sawb" ? wbMagic : nbMagic
            var sample = 0
            for chunk in 1...max(chunkCount, 1) where chunk <= chunkCount && sample < sampleCount {
                let perChunk = runs.last { $0.firstChunk <= chunk }?.samplesPerChunk ?? 0
                var offset = chunkOffsets[chunk - 1]
                for _ in 0..<perChunk where sample < sampleCount {
                    guard offset >= 0, offset + sizes[sample] <= b.count else { return nil }
                    out.append(contentsOf: b[offset..<(offset + sizes[sample])])
                    offset += sizes[sample]
                    sample += 1
                }
            }
            return out
        }
        return nil
    }
}
