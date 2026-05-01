import SloppyComputerControl
import Testing

@Suite("Computer control")
struct ComputerControlTests {
    @Test("click validation rejects negative coordinates")
    func clickValidationRejectsNegativeCoordinates() throws {
        #expect(throws: ComputerControlError.invalidArguments("`x` and `y` must be non-negative finite coordinates.")) {
            try validateClickPayload(ComputerClickPayload(x: -1, y: 20))
        }
    }

    @Test("click validation rejects non-positive rectangle sizes")
    func clickValidationRejectsInvalidSizes() throws {
        #expect(throws: ComputerControlError.invalidArguments("`width` must be positive when provided.")) {
            try validateClickPayload(ComputerClickPayload(x: 1, y: 2, width: 0))
        }
    }
}
