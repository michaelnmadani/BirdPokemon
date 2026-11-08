// swift-tools-version:5.9
// The AMR-NB and AMR-WB *decoders* from opencore-amr 0.1.6 (Apache-2.0), so the
// iPhone app can analyse voice-recorder files — iOS has no AMR decoder.
import PackageDescription

let amr = "opencore/codecs_v2/audio/gsm_amr"

let package = Package(
    name: "OpenCoreAMR",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "OpenCoreAMR", targets: ["AMRNB", "AMRWB"]),
    ],
    targets: [
        .target(
            name: "AMRNB",
            path: "Sources/AMRNB",
            publicHeadersPath: "include",
            cxxSettings: [
                .define("DISABLE_AMRNB_ENCODER"),
                .headerSearchPath("oscl"),
                .headerSearchPath("\(amr)/amr_nb/dec/src"),
                .headerSearchPath("\(amr)/amr_nb/common/include"),
                .headerSearchPath("\(amr)/amr_nb/dec/include"),
                .headerSearchPath("\(amr)/common/dec/include"),
                .headerSearchPath("\(amr)/amr_nb/enc/src"),
            ]
        ),
        .target(
            name: "AMRWB",
            path: "Sources/AMRWB",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("oscl"),
                .headerSearchPath("\(amr)/amr_wb/dec/src"),
                .headerSearchPath("\(amr)/amr_wb/dec/include"),
                .headerSearchPath("\(amr)/common/dec/include"),
            ]
        ),
    ],
    // 2009-era code: uses `register`, which C++17 removed.
    cxxLanguageStandard: .cxx11
)
