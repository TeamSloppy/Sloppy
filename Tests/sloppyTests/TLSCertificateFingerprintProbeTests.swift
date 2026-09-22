import Testing
@testable import sloppy

@Suite("TLS certificate fingerprint probe")
struct TLSCertificateFingerprintProbeTests {
    @Test("extracts the first leaf certificate from OpenSSL output")
    func extractsFirstCertificate() {
        let output = """
        CONNECTED
        -----BEGIN CERTIFICATE-----
        bGVhZg==
        -----END CERTIFICATE-----
        -----BEGIN CERTIFICATE-----
        Y2hhaW4=
        -----END CERTIFICATE-----
        """

        #expect(TLSCertificateFingerprintProbe.firstCertificatePEM(in: output) == """
        -----BEGIN CERTIFICATE-----
        bGVhZg==
        -----END CERTIFICATE-----

        """)
    }
}
