#if os(macOS)
import Foundation
import CryptoKit
import Security
import SecurityInterface

struct BrowserCertificateInfo {
    let trust: SecTrust
    let subject: String
    let issuer: String?
    let validFrom: Date?
    let validUntil: Date?
    let sha256: String

    init?(trust: SecTrust) {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else { return nil }
        self.trust = trust
        subject = SecCertificateCopySubjectSummary(leaf) as String? ?? "Certificate"
        issuer = chain.dropFirst().first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
        validFrom = SecCertificateCopyNotValidBeforeDate(leaf).map { $0 as Date }
        validUntil = SecCertificateCopyNotValidAfterDate(leaf).map { $0 as Date }
        sha256 = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
            .map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    @MainActor
    func showDetails(in window: NSWindow) -> SFCertificatePanel {
        let panel = SFCertificatePanel()
        panel.beginSheet(for: window, modalDelegate: nil, didEnd: nil, contextInfo: nil, trust: trust, showGroup: true)
        panel.certificateView()?.setEditableTrust(false)
        return panel
    }
}
#endif
