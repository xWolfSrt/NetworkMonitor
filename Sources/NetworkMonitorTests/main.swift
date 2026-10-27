import Foundation
import NetworkMonitorCore

// Run with: swift run NetworkMonitorTests
//
// Exits non-zero on any failure, so this works as a pre-commit or CI gate.

if CommandLine.arguments.contains("--localization-preview") {
    try renderLocalizationPreviews()
    exit(0)
}

if CommandLine.arguments.contains("--encoding-fixtures") {
    runNettopTextDecoderTests()
    runNettopEncodingTests()
    exit(Check.summarize())
}

if CommandLine.arguments.contains("--proxy-fixtures") {
    LanguageSettings.shared.select(.english, persist: false)
    runHeadroomLoopbackIntegrationTests()
    runProxyLoopbackIntegrationTests()
    exit(Check.summarize())
}

print("NetworkMonitor test suite")
print(String(repeating: "─", count: 62))

LanguageSettings.shared.select(.simplifiedChinese, persist: false)
Check.suite("Language — default Chinese") {
    Check.test("the interface starts in Simplified Chinese") {
        Check.expectEqual(SettingsPane.allCases.map(\.title), ["通用", "测速", "历史", "热点", "关于"])
    }
}
runLocalizationTests()
LanguageSettings.shared.select(.english, persist: false)
runByteFormatTests()
runMenuBarTitleTests()
runMenuBarColorsTests()
runPowerProfileTests()
runLoginItemTests()
runGatewayProbeTests()
runNettopTextDecoderTests()
runNettopEncodingTests()
runNettopParserTests()
runProxyAttributionTests()
runProxyUsageTests()
runHeadroomAccountingTests()
runRuntimeToolTests()
runLegacyRuntimeAccountingTests()
runHeadroomLoopbackIntegrationTests()
runProxyLoopbackIntegrationTests()
runTrafficScopeTests()
runNettopChildTrackerTests()
runNettopStreamIntegrationTests()
runNettopFailureTests()
runInterfaceClassificationTests()
runInterfaceDeltaTrackerTests()
runRateSmootherTests()
runAppIdentityTests()
runUsageStoreTests()
runUsageHistoryTests()
runSettingsTests()
runUsageRowPartitionTests()
runLiveOrderTests()
runPopoverMetricsTests()
runNetworkFingerprintTests()
runMeteredHeuristicTests()
runSuppressionJournalTests()
runPreferenceSuppressorTests()
runConfigFileSuppressorTests()
runMeteringControllerTests()
runLowDataModeParsingTests()
runInterfaceFlagOwnershipTests()
runLowDataModeSuppressorTests()
runLowDataModeMeteringTests()
runHelperInstallerTests()
runUpdaterScanTests()
runUpdateWatchTests()
runHostsFileTests()
runJSONConfigEditTests()
runSuppressedValueTests()
runSpeedTestTests()
runMenuBarStripTests()
runWindowStackTests()
runWiFiNamesTests()

exit(Check.summarize())
