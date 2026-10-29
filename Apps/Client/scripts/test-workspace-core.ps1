# Run the Foundation-only workspace tests without loading AdaEngine's web plugins.
# First build SloppyClient once to resolve its pinned swift-log checkout.
$ErrorActionPreference = "Stop"
$clientRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = [IO.Path]::GetFullPath((Join-Path $clientRoot "../.."))
$checkRoot = Join-Path $repoRoot ".build/client-workspace-check"
$loggingPath = (Join-Path $clientRoot ".build/checkouts/swift-log").Replace('\', '/')
if (!(Test-Path -LiteralPath "$loggingPath/Package.swift")) {
    throw "Build SloppyClient first to resolve swift-log."
}
foreach ($directory in @("Sources/SloppyClientCore", "Sources/SloppyWorkspace", "Tests/SloppyClientCoreTests", "Tests/SloppyWorkspaceTests")) {
    New-Item -ItemType Directory -Force (Join-Path $checkRoot $directory) | Out-Null
}
Copy-Item "$clientRoot/Sources/SloppyClientCore/*.swift" "$checkRoot/Sources/SloppyClientCore/" -Force
Copy-Item "$clientRoot/Sources/SloppyClient/WorkspaceSurfaceModel.swift" "$checkRoot/Sources/SloppyWorkspace/" -Force
Copy-Item "$clientRoot/Sources/SloppyClient/WorkspaceCanvasModel.swift" "$checkRoot/Sources/SloppyWorkspace/" -Force
foreach ($test in @("WorkspaceNavigationTests", "WorkspaceServiceTests", "ClientSettingsTests", "ConfigPreservationTests", "WorkspaceDocumentsTests", "WorkspaceBrowserRuntimeTests")) {
    Copy-Item "$clientRoot/Tests/SloppyClientCoreTests/$test.swift" "$checkRoot/Tests/SloppyClientCoreTests/" -Force
}
Copy-Item "$clientRoot/Sources/SloppyFeatureChat/ChatComposerSuggestions.swift" "$checkRoot/Sources/SloppyWorkspace/" -Force
Copy-Item "$clientRoot/Sources/SloppyFeatureChat/ChatComposerSuggestionModel.swift" "$checkRoot/Sources/SloppyWorkspace/" -Force
$composerTests = Get-Content "$clientRoot/Tests/SloppyFeatureChatTests/ChatComposerSuggestionsTests.swift" -Raw
$composerTests.Replace("@testable import SloppyFeatureChat", "@testable import SloppyWorkspace") |
    Set-Content "$checkRoot/Tests/SloppyWorkspaceTests/ChatComposerSuggestionsTests.swift" -Encoding utf8
$surfaceTests = Get-Content "$clientRoot/Tests/SloppyClientWorkspaceTests/WorkspaceSurfaceTests.swift" -Raw
$surfaceTests.Replace("@testable import SloppyClient`n", "@testable import SloppyWorkspace`n").Replace("@testable import SloppyClient`r`n", "@testable import SloppyWorkspace`r`n") |
    Set-Content "$checkRoot/Tests/SloppyWorkspaceTests/WorkspaceSurfaceTests.swift" -Encoding utf8
@"
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "WorkspaceCoreCheck", dependencies: [.package(path: "$loggingPath")], targets: [
    .target(name: "SloppyClientCore", dependencies: [.product(name: "Logging", package: "swift-log")]),
    .target(name: "SloppyWorkspace", dependencies: ["SloppyClientCore"]),
    .testTarget(name: "SloppyClientCoreTests", dependencies: ["SloppyClientCore"]),
    .testTarget(name: "SloppyWorkspaceTests", dependencies: ["SloppyWorkspace", "SloppyClientCore"]),
])
"@ | Set-Content "$checkRoot/Package.swift" -Encoding utf8
& swift test --package-path $checkRoot --jobs 2
if ($LASTEXITCODE -ne 0) { throw "Workspace tests failed (exit $LASTEXITCODE)." }
