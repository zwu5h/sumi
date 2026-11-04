"""Run actual store batch logic with PDFKit/UI test doubles on a Swift host.

This checks orchestration and file cleanup; real PDF decoding and rendering still
require the iOS build/runtime. Only imports and the sandbox destination are adapted.
"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="sumi-import-") as directory:
    directory = Path(directory)
    source = (root / "Sources/Sumi/LibraryStore.swift").read_text(encoding="utf-8")
    source = source.replace("import PDFKit\n", "").replace("import SwiftUI\n", "")
    source = source.replace(
        "FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]",
        'URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUMI_IMPORT_TEST_DIRECTORY"]!)',
    )
    adapted = directory / "LibraryStore.swift"
    adapted.write_text(source, encoding="utf-8")
    # Linux Foundation lacks URLSession.bytes. Keep the production request builder
    # and redirect delegate verbatim; the iOS build checks the streaming download.
    network = (root / "Sources/Sumi/SourceNetwork.swift").read_text(encoding="utf-8")
    network = network.split("    static func get(", 1)[0] + "}\n"
    network = network.replace("import Foundation\n", "import Foundation\n#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\n", 1)
    adapted_network = directory / "SourceNetwork.swift"
    adapted_network.write_text(network, encoding="utf-8")
    executable = directory / "library-import-checks"
    subprocess.run([
        "swiftc", "-swift-version", "5", str(adapted),
        str(root / "Sources/Sumi/ReadingPosition.swift"),
        str(root / "Sources/Sumi/SourceModels.swift"),
        str(adapted_network), str(root / "Tests/SourceNetworkChecks.swift"),
        str(root / "Tests/SourceChecks.swift"),
        str(root / "Tests/LibraryImportChecks.swift"), "-o", str(executable),
    ], check=True)
    environment = dict(os.environ, SUMI_IMPORT_TEST_DIRECTORY=str(directory / "documents"),
                       XDG_CONFIG_HOME=str(directory / "preferences"))
    subprocess.run([str(executable)], env=environment, check=True)
