import Foundation
import XCTest

@testable import FluidAudio

final class PocketTtsWholeSentenceTests: XCTestCase {

    private let numberWords = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve",
    ]

    /// One token per word and per punctuation mark.
    private func makeTokenizer() throws -> SentencePieceTokenizer {
        let letters = "abcdefghijklmnopqrstuvwxyz".map { String($0) }
        return try SentencePieceTestModel.tokenizer(
            pieces: ["<unk>", "\u{2581}", ".", ","] + numberWords.map { "\u{2581}" + $0 } + letters)
    }

    private let text = "one two three. four five six, seven eight nine ten eleven twelve."

    func testSentenceOverTheChunkCapStaysWholeWhenItFitsTheCache() throws {
        // The second sentence is 11 tokens against a chunk cap of 8.
        let chunks = PocketTtsSynthesizer.chunkTextWithMetadata(
            text, tokenizer: try makeTokenizer(), maxTokens: 8, maxWholeSentenceTokens: 12)
        XCTAssertEqual(
            chunks,
            [
                PocketTtsSynthesizer.TextChunk(text: "one two three.", isMidSentence: false),
                PocketTtsSynthesizer.TextChunk(
                    text: "four five six, seven eight nine ten eleven twelve.", isMidSentence: false),
            ])
    }

    func testSentenceOverTheCacheBudgetIsStillCut() throws {
        let chunks = PocketTtsSynthesizer.chunkTextWithMetadata(
            text, tokenizer: try makeTokenizer(), maxTokens: 8, maxWholeSentenceTokens: 10)
        // The head of the cut sentence joins the sentence before it, since the
        // two fit the chunk cap together.
        XCTAssertEqual(
            chunks.map(\.text),
            ["one two three. four five six,", "seven eight nine ten eleven twelve."])
        XCTAssertEqual(chunks.map(\.isMidSentence), [false, true])
    }

    func testOmittingTheBudgetKeepsTheChunkCapAsTheOnlyLimit() throws {
        let tokenizer = try makeTokenizer()
        XCTAssertEqual(
            PocketTtsSynthesizer.chunkTextWithMetadata(text, tokenizer: tokenizer, maxTokens: 8),
            PocketTtsSynthesizer.chunkTextWithMetadata(
                text, tokenizer: tokenizer, maxTokens: 8, maxWholeSentenceTokens: 0))
    }

    func testWholeSentenceBudgetComesFromTheCacheAndTheVoice() {
        // 512 slots, 8 held back, 1 slot per token plus 4 per token for audio.
        XCTAssertEqual(PocketTtsSynthesizer.maxWholeSentenceTokens(voiceSlots: 126), 75)
        XCTAssertEqual(PocketTtsSynthesizer.maxWholeSentenceTokens(voiceSlots: 251), 50)
        XCTAssertEqual(PocketTtsSynthesizer.maxWholeSentenceTokens(voiceSlots: 600), 0)
    }

    func testStepLimitNeverRunsPastTheCache() {
        let long = Array(repeating: "word", count: 60).joined(separator: " ")
        XCTAssertEqual(PocketTtsSynthesizer.generationStepLimit(text: long, cachePosition: 200), 312)
        XCTAssertEqual(PocketTtsSynthesizer.generationStepLimit(text: long, cachePosition: 512), 0)
        XCTAssertEqual(
            PocketTtsSynthesizer.generationStepLimit(text: "two words", cachePosition: 200),
            PocketTtsSynthesizer.estimateMaxFrames(text: "two words"))
    }

    func testVoiceFootprintCountsTheBosRowForClonedVoices() {
        let cloned = PocketTtsVoiceData(audioPrompt: [], promptLength: 125)
        XCTAssertEqual(cloned.cacheSlots, 126)
    }
}
