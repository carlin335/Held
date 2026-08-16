//
//  CardScannerEngine.swift
//  CardSenseApp
//
//  Created by Carlin Jon Soorenian on 10/7/25.
//
// CardScannerEngine.swift — fast, confidence-gated collectible recognition
//
// - Detects and perspective-corrects steady card/label geometry.
// - Runs title and collector-number OCR together on the latest camera frame.
// - Requires independent frames to agree before returning an identity.
// - Supports category-specific metadata for TCG, sports, coins and wine.

import Foundation
import Vision
import CoreImage
import CoreMedia
import CoreImage.CIFilterBuiltins
import QuartzCore   // CACurrentMediaTime()

// MARK: - Sliding-window consensus

/// OCR is noisy even when the item is still. This vote keeps the original
/// display spelling while grouping harmless case, accent, width and punctuation
/// differences (for example, "Pokemon" and "Pokémon") into one identity.
private final class TextConsensus {
    private struct Sample {
        let value: String
        let key: String
        let confidence: Float
    }

    struct Winner {
        let value: String
        let count: Int
        let confidence: Float
    }

    private let capacity: Int
    private var samples: [Sample] = []

    init(capacity: Int = 6) {
        self.capacity = max(1, capacity)
    }

    func push(_ value: String, confidence: Float = 0) {
        let display = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.identityKey(display)
        guard !display.isEmpty, !key.isEmpty else { return }
        samples.append(Sample(value: display, key: key, confidence: confidence))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    var winner: Winner? {
        guard !samples.isEmpty else { return nil }
        let counts = samples.reduce(into: [String: Int]()) { counts, sample in
            counts[sample.key, default: 0] += 1
        }
        guard let highestCount = counts.values.max() else { return nil }

        // A recent reading wins ties so an old object cannot hold the scanner.
        guard let winningKey = samples.reversed().first(where: {
            counts[$0.key] == highestCount
        })?.key else { return nil }

        let matching = samples.filter { $0.key == winningKey }
        guard let bestSample = matching.enumerated().max(by: { lhs, rhs in
            if lhs.element.confidence == rhs.element.confidence {
                return lhs.offset < rhs.offset
            }
            return lhs.element.confidence < rhs.element.confidence
        })?.element else { return nil }

        return Winner(
            value: bestSample.value,
            count: highestCount,
            confidence: bestSample.confidence
        )
    }

    var best: String? { winner?.value }
    var bestCount: Int { winner?.count ?? 0 }

    func agrees(with value: String?) -> Bool {
        guard let value, let currentWinner = winner else { return false }
        return Self.identityKey(value) == Self.identityKey(currentWinner.value)
    }

    func clear() {
        samples.removeAll(keepingCapacity: true)
    }

    private static func identityKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

// MARK: - Tuning

private struct Tune {
    // Rectangle detector. Trading cards are ~0.715 (short edge / long edge),
    // but the wider range also accepts holders and mild perspective skew.
    static let minAspect: Float = 0.62
    static let maxAspect: Float = 0.90
    static let minSize:   Float = 0.10
    static let minRectangleConfidence: Float = 0.32
    static let stableRectangleIOU: CGFloat = 0.62
    static let maxRectangleAreaChange: CGFloat = 0.18
    static let stableRectangleFrames = 2

    // Capture cadence. AVCaptureVideoDataOutput drops frames while Vision is
    // busy, so every accepted buffer is current rather than queued camera data.
    static let minGap: CFTimeInterval = 0.12
    static let rectangleMissesBeforeFallback = 2

    // OCR thresholds
    static let needNameConf: Float = 0.48
    // Tiny collector numbers often score lower than titles under household
    // lighting. Two-frame consensus supplies the safety, so each individual
    // number read can use a slightly lower threshold without trusting one frame.
    static let needNumConf:  Float = 0.34
    static let numberMinimumTextHeight: Float = 0.005
    static let votesWithStableGeometry = 2
    static let votesWithoutGeometry = 3
    static let attemptsBeforePartialResult = 5
}

// MARK: - Helpers

private extension String {
    var isMostlyNumericLike: Bool {
        let digits = filter { $0.isNumber }.count
        return digits >= max(3, count / 2)
    }
}

// MARK: - Engine

public final class CardScannerEngine {

    private let handlerOpts: [VNImageOption: Any] = [:]
    private let stateLock = NSLock()

    // Identity and metadata votes. An answer is never emitted from a single
    // weak frame; at least two stable reads (three without geometry) must agree.
    private let nameVote = TextConsensus(capacity: 6)
    private let numVote  = TextConsensus(capacity: 6)
    private let printedNumVote = TextConsensus(capacity: 6)
    private var metadataVotes: [MetadataField: TextConsensus] = [:]

    // Capture cadence and scene stability.
    private var last: CFTimeInterval = 0
    private var previousRectangle: CGRect?
    private var stableRectangleFrames = 0
    private var rectangleMisses = 0
    private var ocrAttempts = 0

    // Language hints
    private let mixedHints: [String]
    private let jaHints    = ["ja-JP", "ja"]
    private let enHints    = ["en-US", "en"]
    private let game: Game
    private let pokemonLanguage: PokemonScanLanguage

    private var tradingCardAutodetectsLanguage: Bool {
        guard game == .pokemon else { return true }
        return pokemonLanguage != .japanese
    }

    private var shouldTryJapanese: Bool {
        game == .pokemon && pokemonLanguage != .english
    }

    private var shouldTryEnglish: Bool {
        game != .pokemon || pokemonLanguage != .japanese
    }

    private var numberLanguageHints: [String] {
        game == .pokemon ? pokemonLanguage.ocrLanguageHints : enHints
    }

    private var ocrCustomWords: [String] {
        switch game {
        case .pokemon:
            return [
                "Pokémon", "Pokemon", "ex", "EX", "V", "VMAX", "VSTAR", "V-UNION", "GX",
                "BREAK", "LV.X", "LEGEND", "Prime", "Radiant", "Shining", "Mega", "Tera",
                "Prism Star", "TAG TEAM", "Delta Species", "Dark", "Light", "Owner's",
                "SAR", "CHR", "HP", "ポケモン", "ＨＰ"
            ]
        case .magic:
            return ["Planeswalker", "Legendary", "Creature", "Sorcery", "Instant", "Enchantment", "Artifact"]
        case .yugioh:
            return ["Yu-Gi-Oh!", "ATK", "DEF", "SPELL", "TRAP", "TUNER", "SYNCHRO", "XYZ", "LINK"]
        case .sports:
            return [
                "Topps", "Topps Chrome", "Panini", "Upper Deck", "Bowman", "Bowman Chrome",
                "Donruss", "Fleer", "Score", "Leaf", "O-Pee-Chee", "SkyBox", "Prizm",
                "Optic", "Mosaic", "Select", "Contenders", "National Treasures", "Flawless",
                "Immaculate", "Refractor", "Superfractor", "Rookie", "RC", "Autograph", "Auto"
            ]
        case .coins:
            return ["Cent", "Cents", "Penny", "Dime", "Quarter", "Dollar", "Euro", "Pound", "Peso", "Franc"]
        case .wine:
            return ["Cabernet", "Sauvignon", "Chardonnay", "Merlot", "Pinot", "Riesling", "Syrah", "Shiraz", "Champagne", "Prosecco"]
        case .other:
            return []
        }
    }

    public init(
        languages: [String] = ["ja-JP","ja","en-US","en"],
        game: Game = .pokemon,
        pokemonLanguage: PokemonScanLanguage = .english
    ) {
        self.mixedHints = languages.isEmpty ? ["ja-JP","ja","en-US","en"] : languages
        self.game = game
        self.pokemonLanguage = pokemonLanguage
    }

    public func reset() {
        stateLock.lock()
        defer { stateLock.unlock() }
        clearRecognitionVotes()
        previousRectangle = nil
        stableRectangleFrames = 0
        rectangleMisses = 0
        last = 0
    }

    private enum MetadataField: Hashable {
        case year, brand, setName, parallel, serialNumber
        case country, denomination, mintMark
        case producer, region, varietal, bottleSize, alcoholByVolume
    }

    // MARK: - Main

    public func process(sampleBuffer: CMSampleBuffer) -> ScanHit? {
        stateLock.lock()
        defer { stateLock.unlock() }

        let now = CACurrentMediaTime()
        guard now - last >= Tune.minGap else { return nil }
        last = now

        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let source = CIImage(cvImageBuffer: pixel)

        // Detect on the unfiltered camera buffer. Expensive enhancement and OCR
        // only run after the card is steady, which keeps the capture queue fresh.
        let rectObs = shouldDetectRectangle ? detectRectangle(in: source) : nil
        let geometryStable = updateGeometry(with: rectObs)
        let usesStableCardGeometry = isCardGame && geometryStable && rectObs != nil

        if isCardGame {
            if rectObs != nil, !geometryStable { return nil }
            if rectObs == nil, rectangleMisses < Tune.rectangleMissesBeforeFallback { return nil }
        }

        // Perspective-correct cards/labels when Vision found their edges. A
        // center crop remains available for borderless, sleeved or edge-clipped
        // cards and for round/free-form collectibles.
        var corrected: CIImage
        if let r = rectObs {
            corrected = perspectiveCorrect(source, rect: r)
            if !rectIsUsable(corrected.extent) { corrected = centerFallback(source) }
        } else {
            corrected = centerFallback(source)
        }
        if corrected.extent.width > corrected.extent.height { corrected = corrected.oriented(.left) }
        guard rectIsUsable(corrected.extent) else { return nil }
        // Keep an un-denoised source for the tiny printed identifier. The main
        // pass remains optimized for titles and normal-sized label text.
        let collectorNumberSource = corrected
        corrected = preprocess(corrected)
        ocrAttempts += 1

        let requiredVotes = usesStableCardGeometry
            ? Tune.votesWithStableGeometry
            : Tune.votesWithoutGeometry

        if game == .sports {
            return processSportsCard(
                corrected,
                rawImage: collectorNumberSource,
                requiredVotes: requiredVotes
            )
        }
        if game == .coins {
            return processCoin(corrected, requiredVotes: requiredVotes)
        }
        if game == .wine {
            return processWine(corrected, requiredVotes: requiredVotes)
        }
        if game == .other {
            return processGeneralCollectible(corrected, requiredVotes: requiredVotes)
        }

        // 3) Internal OCR regions (pixel space) for title and collector number.
        let ext = corrected.extent
        let W = ext.width, H = ext.height
        let nameBand: CGRect
        if game == .pokemon {
            // Pokémon names can include long, meaningful printed suffixes such
            // as ex, VMAX, VSTAR, V-UNION, GX, BREAK, and LV.X. Keep more of
            // the top line while stopping short of the far-right HP value.
            nameBand = CGRect(x: W*0.035, y: H*0.75, width: W*0.83, height: H*0.20)
        } else {
            nameBand = CGRect(x: W*0.06, y: H*0.76, width: W*0.62, height: H*0.18)
        }
        let numBand: CGRect
        if game == .pokemon {
            // Modern Pokémon collector numbers sit almost on the lower border.
            // The old band started at 6% and could exclude the entire 021/086
            // line visible in real camera tests.
            numBand = CGRect(x: W*0.015, y: H*0.002, width: W*0.62, height: H*0.13)
        } else {
            numBand = CGRect(x: W*0.04, y: H*0.025, width: W*0.54, height: H*0.17)
        }

        // Run the primary title and number requests together so Vision only
        // prepares this frame once. Title favors accuracy; the numeric region
        // favors speed and disables language correction.
        let primaryOCR = ocrTradingCard(
            corrected,
            nameROI: nameBand,
            numberROI: numBand,
            hints: mixedHints,
            autodetect: tradingCardAutodetectsLanguage
        )

        // ---- NAME: two-pass ----
        var nameResult = primaryOCR.name
        if shouldTryJapanese,
           (pokemonLanguage == .japanese
                || (nameResult?.1 ?? 0) < Tune.needNameConf
                || (nameResult?.0.containsJapaneseScriptForHeld ?? false)) {
            if let r2 = ocrName(corrected, roiPixel: nameBand, hints: jaHints, autodetect: false),
               r2.1 >= (nameResult?.1 ?? 0) {
                nameResult = r2
            }
        }
        if shouldTryEnglish,
           !(nameResult?.0.containsJapaneseScriptForHeld ?? false),
           (nameResult?.1 ?? 0) < (Tune.needNameConf + 0.10),
           let r2 = ocrName(corrected, roiPixel: nameBand, hints: enHints, autodetect: false),
           r2.1 > (nameResult?.1 ?? 0) {
            nameResult = r2
        }

        // ---- NUMBER: two-pass ----
        var numResult = primaryOCR.number
        if (numResult?.1 ?? 0) < Tune.needNumConf {
            if let r2 = ocrCollectorNumber(
                collectorNumberSource,
                roiPixel: numBand,
                hints: numberLanguageHints,
                recognitionLevel: .fast
            ),
               r2.1 >= (numResult?.1 ?? 0) {
                numResult = r2
            }
        }

        // Optional widen if weak
        var nameBest = cleanName(nameResult?.0)
        var nameConf = nameResult?.1 ?? 0
        var rawNum   = extractNumberRaw(numResult?.0 ?? "")
        var shortNum = reduceLeftNumber(rawNum)
        var numConf  = numResult?.1 ?? 0

        if (nameBest == nil || nameConf < Tune.needNameConf) || (shortNum == nil || numConf < Tune.needNumConf) {
            let nameWide = inflate(nameBand, w: W, h: H, dx: 0.04, dy: 0.02)
            let numWide  = inflate(numBand,  w: W, h: H, dx: 0.03, dy: 0.00)

            var nm = ocrName(
                corrected,
                roiPixel: nameWide,
                hints: mixedHints,
                autodetect: tradingCardAutodetectsLanguage
            )
            if shouldTryJapanese,
               (pokemonLanguage == .japanese
                    || (nm?.1 ?? 0) < Tune.needNameConf
                    || (nm?.0.containsJapaneseScriptForHeld ?? false)) {
                if let r2 = ocrName(corrected, roiPixel: nameWide, hints: jaHints, autodetect: false),
                   r2.1 >= (nm?.1 ?? 0) { nm = r2 }
            }
            if shouldTryEnglish,
               !(nm?.0.containsJapaneseScriptForHeld ?? false),
               (nm?.1 ?? 0) < (Tune.needNameConf + 0.10),
               let r2 = ocrName(corrected, roiPixel: nameWide, hints: enHints, autodetect: false),
               r2.1 > (nm?.1 ?? 0) {
                nm = r2
            }
            if let n2 = nm, n2.1 > nameConf { nameBest = cleanName(n2.0); nameConf = n2.1 }

            var nb = ocrCollectorNumber(
                collectorNumberSource,
                roiPixel: numWide,
                hints: numberLanguageHints,
                recognitionLevel: .fast
            )
            if (nb?.1 ?? 0) < Tune.needNumConf {
                if let r2 = ocrAll(
                    corrected,
                    roiPixel: numWide,
                    hints: numberLanguageHints,
                    autodetect: false,
                    recognitionLevel: .fast,
                    usesLanguageCorrection: false,
                    minimumTextHeight: Tune.numberMinimumTextHeight
                ),
                   r2.1 >= (nb?.1 ?? 0) { nb = r2 }
            }
            if let m2 = nb, m2.1 > numConf {
                rawNum   = extractNumberRaw(m2.0) ?? rawNum
                shortNum = reduceLeftNumber(rawNum) ?? shortNum
                numConf  = m2.1
            }
        }

        // Last-ditch number sweep
        if (shortNum == nil || numConf < Tune.needNumConf), ocrAttempts >= 2 {
            let fullBottom = CGRect(x: W*0.005, y: 0, width: W*0.99, height: H*0.19)
            if let sweep = ocrCollectorNumber(
                collectorNumberSource,
                roiPixel: fullBottom,
                hints: numberLanguageHints,
                recognitionLevel: .accurate
            ),
               let r = extractNumberRaw(sweep.0) {
                rawNum   = r
                shortNum = reduceLeftNumber(r)
                numConf  = max(numConf, sweep.1)
            }
        }

        // Stabilize independent Vision reads before returning an identity.
        if let n = nameBest, nameConf >= Tune.needNameConf {
            nameVote.push(n, confidence: nameConf)
        }
        if let m = shortNum, numConf >= Tune.needNumConf {
            numVote.push(m, confidence: numConf)
            if let rawNum { printedNumVote.push(rawNum, confidence: numConf) }
        }

        guard nameVote.agrees(with: nameBest),
              let nameWinner = nameVote.winner,
              nameWinner.count >= requiredVotes else { return nil }

        let numberWinner = numVote.winner
        if shortNum != nil, !numVote.agrees(with: shortNum) { return nil }
        let lockedNumber = (numberWinner?.count ?? 0) >= 2 ? numberWinner?.value : nil
        let printedWinner = printedNumVote.winner
        let lockedPrintedNumber: String?
        if let lockedNumber,
           let printedWinner,
           printedWinner.count >= 2,
           reduceLeftNumber(printedWinner.value) == lockedNumber {
            lockedPrintedNumber = printedWinner.value
        } else {
            lockedPrintedNumber = lockedNumber
        }

        // A Pokémon name alone cannot identify the exact printing or its price.
        // Keep reading instead of showing a confident but wrong market match.
        if game == .pokemon, lockedNumber == nil { return nil }

        // Other card types can still return a verified title after several
        // attempts because some products do not print a collector number.
        if lockedNumber == nil, ocrAttempts < Tune.attemptsBeforePartialResult {
            return nil
        }
        return ScanHit(
            name: nameWinner.value,
            number: lockedNumber,
            printedNumber: lockedPrintedNumber
        )
    }

    private func processSportsCard(
        _ image: CIImage,
        rawImage: CIImage,
        requiredVotes: Int
    ) -> ScanHit? {
        let extent = image.extent
        let fullCard = CGRect(
            x: extent.width * 0.03,
            y: extent.height * 0.03,
            width: extent.width * 0.94,
            height: extent.height * 0.94
        )
        guard let primary = ocrAll(
            image,
            roiPixel: fullCard,
            hints: mixedHints,
            autodetect: true,
            recognitionLevel: .accurate,
            usesLanguageCorrection: true,
            minimumTextHeight: 0.008
        ), primary.1 >= 0.28 else { return nil }

        var combinedText = primary.0
        var combinedConfidence = primary.1
        var metadata = SportsCardParser.parse(combinedText)

        // Sports cards often put the card number, copyright year, and product
        // name in very small type. If the clean pass did not find enough clues,
        // re-read the unfiltered card at a lower text-height threshold.
        let needsFinePrint = metadata.cardNumber == nil
            || metadata.year == nil
            || (metadata.brand == nil && metadata.setName == nil)
        if needsFinePrint, ocrAttempts >= 2 {
            let rawExtent = rawImage.extent
            let rawCard = CGRect(
                x: rawExtent.width * 0.02,
                y: rawExtent.height * 0.02,
                width: rawExtent.width * 0.96,
                height: rawExtent.height * 0.96
            )
            if let fine = ocrAll(
                rawImage,
                roiPixel: rawCard,
                hints: mixedHints,
                autodetect: true,
                recognitionLevel: .accurate,
                usesLanguageCorrection: true,
                minimumTextHeight: 0.005
            ) {
                combinedText += "\n" + fine.0
                combinedConfidence = max(combinedConfidence, fine.1)
                metadata = SportsCardParser.parse(combinedText)
            }
        }

        // Some modern designs print the player vertically. Only when a player
        // is still missing, try one rotated read instead of slowing every scan.
        if metadata.player == nil, ocrAttempts >= 3 {
            let rotated = image.oriented(
                ocrAttempts.isMultiple(of: 2) ? .left : .right
            )
            let rotatedExtent = rotated.extent
            if let vertical = ocrAll(
                rotated,
                roiPixel: CGRect(origin: .zero, size: rotatedExtent.size),
                hints: mixedHints,
                autodetect: true,
                recognitionLevel: .accurate,
                usesLanguageCorrection: true,
                minimumTextHeight: 0.008
            ) {
                combinedText += "\n" + vertical.0
                combinedConfidence = max(combinedConfidence, vertical.1)
                metadata = SportsCardParser.parse(combinedText)
            }
        }

        let identity = metadata.player ?? SportsCardParser.identityLabel(for: metadata)
        guard let identity, !identity.isEmpty else { return nil }
        nameVote.push(identity, confidence: combinedConfidence)
        if let number = metadata.cardNumber, !number.isEmpty {
            numVote.push(number, confidence: combinedConfidence)
        }
        record(metadata.year, for: .year, confidence: combinedConfidence)
        record(metadata.brand, for: .brand, confidence: combinedConfidence)
        record(metadata.setName, for: .setName, confidence: combinedConfidence)
        record(metadata.parallel, for: .parallel, confidence: combinedConfidence)
        record(metadata.serialNumber, for: .serialNumber, confidence: combinedConfidence)

        guard nameVote.agrees(with: identity),
              let identityWinner = nameVote.winner,
              identityWinner.count >= requiredVotes else { return nil }
        let numberWinner = numVote.winner
        if metadata.cardNumber != nil, !numVote.agrees(with: metadata.cardNumber) { return nil }
        let cardNumber = (numberWinner?.count ?? 0) >= 2 ? numberWinner?.value : nil
        let hasStableProductClue = stableMetadata(.year) != nil
            || stableMetadata(.brand) != nil
            || stableMetadata(.setName) != nil
        if cardNumber == nil,
           !hasStableProductClue,
           ocrAttempts < 4 { return nil }

        if metadata.player != nil { metadata.player = identityWinner.value }
        metadata.cardNumber = cardNumber
        metadata.year = stableMetadata(.year)
        metadata.brand = stableMetadata(.brand)
        metadata.setName = stableMetadata(.setName)
        metadata.parallel = stableMetadata(.parallel)
        metadata.serialNumber = stableMetadata(.serialNumber)
        return ScanHit(
            name: metadata.player ?? identityWinner.value,
            number: metadata.cardNumber,
            sportsMetadata: metadata
        )
    }

    private func processCoin(_ image: CIImage, requiredVotes: Int) -> ScanHit? {
        guard let result = fullCardOCR(image), result.1 >= 0.28 else { return nil }
        let metadata = CoinParser.parse(result.0)
        guard metadata.year != nil || metadata.denomination != nil else { return nil }
        if let title = metadata.title, !title.isEmpty {
            nameVote.push(title, confidence: result.1)
        }
        if let year = metadata.year, !year.isEmpty {
            numVote.push(year, confidence: result.1)
        }
        record(metadata.country, for: .country, confidence: result.1)
        record(metadata.denomination, for: .denomination, confidence: result.1)
        record(metadata.mintMark, for: .mintMark, confidence: result.1)

        guard nameVote.agrees(with: metadata.title),
              let titleWinner = nameVote.winner,
              titleWinner.count >= requiredVotes else { return nil }
        var stable = metadata
        stable.title = titleWinner.value
        stable.year = numVote.bestCount >= 2 ? numVote.best : nil
        stable.country = stableMetadata(.country)
        stable.denomination = stableMetadata(.denomination)
        stable.mintMark = stableMetadata(.mintMark)
        return ScanHit(name: titleWinner.value, number: stable.year, coinMetadata: stable)
    }

    private func processWine(_ image: CIImage, requiredVotes: Int) -> ScanHit? {
        guard let result = fullCardOCR(image), result.1 >= 0.28 else { return nil }
        let metadata = WineParser.parse(result.0)
        guard metadata.wineName != nil, metadata.wineName != "Unidentified wine" else { return nil }
        if let name = metadata.wineName, !name.isEmpty {
            nameVote.push(name, confidence: result.1)
        }
        if let vintage = metadata.vintage, !vintage.isEmpty {
            numVote.push(vintage, confidence: result.1)
        }
        record(metadata.producer, for: .producer, confidence: result.1)
        record(metadata.region, for: .region, confidence: result.1)
        record(metadata.country, for: .country, confidence: result.1)
        record(metadata.varietal, for: .varietal, confidence: result.1)
        record(metadata.bottleSize, for: .bottleSize, confidence: result.1)
        record(metadata.alcoholByVolume, for: .alcoholByVolume, confidence: result.1)

        guard nameVote.agrees(with: metadata.wineName),
              let nameWinner = nameVote.winner,
              nameWinner.count >= requiredVotes else { return nil }
        var stable = metadata
        stable.wineName = nameWinner.value
        stable.vintage = numVote.bestCount >= 2 ? numVote.best : nil
        stable.producer = stableMetadata(.producer)
        stable.region = stableMetadata(.region)
        stable.country = stableMetadata(.country)
        stable.varietal = stableMetadata(.varietal)
        stable.bottleSize = stableMetadata(.bottleSize)
        stable.alcoholByVolume = stableMetadata(.alcoholByVolume)
        return ScanHit(name: nameWinner.value, number: stable.vintage, wineMetadata: stable)
    }

    private func processGeneralCollectible(_ image: CIImage, requiredVotes: Int) -> ScanHit? {
        guard let result = fullCardOCR(image), result.1 >= 0.30 else { return nil }
        let lines = result.0.split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 && $0.count <= 60 }
        let name = lines
            .filter { $0.range(of: #"\d"#, options: .regularExpression) == nil }
            .max { $0.count < $1.count }
        let year = result.0.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression)
            .map { String(result.0[$0]) }
        if let name { nameVote.push(name, confidence: result.1) }
        if let year { numVote.push(year, confidence: result.1) }
        guard nameVote.agrees(with: name),
              let nameWinner = nameVote.winner,
              nameWinner.count >= requiredVotes else { return nil }
        let stableYear = numVote.bestCount >= 2 ? numVote.best : nil
        return ScanHit(name: nameWinner.value, number: stableYear)
    }

    private func fullCardOCR(_ image: CIImage) -> (String, Float)? {
        let extent = image.extent
        return ocrAll(
            image,
            roiPixel: CGRect(
                x: extent.width * 0.03,
                y: extent.height * 0.03,
                width: extent.width * 0.94,
                height: extent.height * 0.94
            ),
            hints: mixedHints,
            autodetect: true
        )
    }

    // MARK: - Scene stability and metadata consensus

    private var isCardGame: Bool {
        switch game {
        case .pokemon, .magic, .yugioh, .sports: return true
        case .coins, .wine, .other: return false
        }
    }

    private var shouldDetectRectangle: Bool {
        // Round coins are intentionally excluded; a rectangular background or
        // coin flip would be a worse crop than the centered capture area.
        game != .coins
    }

    private func detectRectangle(in image: CIImage) -> VNRectangleObservation? {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = isCardGame ? Tune.minAspect : 0.34
        request.maximumAspectRatio = isCardGame ? Tune.maxAspect : 1.0
        request.minimumSize = isCardGame ? Tune.minSize : 0.08
        request.maximumObservations = 1
        request.quadratureTolerance = isCardGame ? 28 : 35
        if #available(iOS 16.0, *) {
            request.minimumConfidence = Tune.minRectangleConfidence
        }

        do {
            try VNImageRequestHandler(ciImage: image, options: handlerOpts).perform([request])
            return request.results?.first
        } catch {
            return nil
        }
    }

    /// Returns true once two consecutive card rectangles agree in position and
    /// size. A meaningful move clears every OCR vote, preventing clues from two
    /// different collectibles from being merged into one false identity.
    private func updateGeometry(with rectangle: VNRectangleObservation?) -> Bool {
        guard isCardGame else { return false }

        guard let rectangle else {
            rectangleMisses += 1
            if rectangleMisses == Tune.rectangleMissesBeforeFallback {
                previousRectangle = nil
                stableRectangleFrames = 0
                clearRecognitionVotes()
            }
            return false
        }

        let hadFallbackFrames = rectangleMisses >= Tune.rectangleMissesBeforeFallback
        rectangleMisses = 0
        let current = rectangle.boundingBox

        if let previousRectangle {
            let previousArea = previousRectangle.width * previousRectangle.height
            let currentArea = current.width * current.height
            let areaChange = abs(currentArea - previousArea) / max(max(previousArea, currentArea), 1e-6)
            let isSteady = intersectionOverUnion(current, previousRectangle) >= Tune.stableRectangleIOU
                && areaChange <= Tune.maxRectangleAreaChange

            if isSteady {
                stableRectangleFrames += 1
            } else {
                stableRectangleFrames = 1
                clearRecognitionVotes()
            }
        } else {
            stableRectangleFrames = 1
            if hadFallbackFrames { clearRecognitionVotes() }
        }

        previousRectangle = current
        return stableRectangleFrames >= Tune.stableRectangleFrames
    }

    private func clearRecognitionVotes() {
        nameVote.clear()
        numVote.clear()
        printedNumVote.clear()
        metadataVotes.values.forEach { $0.clear() }
        metadataVotes.removeAll(keepingCapacity: true)
        ocrAttempts = 0
    }

    private func record(_ value: String?, for field: MetadataField, confidence: Float) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let vote: TextConsensus
        if let existing = metadataVotes[field] {
            vote = existing
        } else {
            vote = TextConsensus(capacity: 6)
            metadataVotes[field] = vote
        }
        vote.push(value, confidence: confidence)
    }

    private func stableMetadata(_ field: MetadataField, minimumVotes: Int = 2) -> String? {
        guard let winner = metadataVotes[field]?.winner,
              winner.count >= minimumVotes else { return nil }
        return winner.value
    }

    // MARK: - OCR helpers

    private func ocrTradingCard(
        _ image: CIImage,
        nameROI: CGRect,
        numberROI: CGRect,
        hints: [String],
        autodetect: Bool
    ) -> (name: (String, Float)?, number: (String, Float)?) {
        let normalizedName = normalize(nameROI, in: image.extent)
        let normalizedNumber = normalize(numberROI, in: image.extent)
        guard normalizedName.width > 0, normalizedName.height > 0,
              normalizedNumber.width > 0, normalizedNumber.height > 0 else {
            return (nil, nil)
        }

        let nameRequest = makeRequest(
            hints: hints,
            autodetect: autodetect,
            recognitionLevel: .accurate,
            usesLanguageCorrection: true
        )
        nameRequest.regionOfInterest = normalizedName

        let numberRequest = makeRequest(
            hints: hints,
            autodetect: autodetect,
            recognitionLevel: .fast,
            usesLanguageCorrection: false,
            minimumTextHeight: Tune.numberMinimumTextHeight
        )
        numberRequest.regionOfInterest = normalizedNumber

        do {
            try VNImageRequestHandler(ciImage: image, options: handlerOpts)
                .perform([nameRequest, numberRequest])
        } catch {
            return (nil, nil)
        }

        let name = bestTitle(from: nameRequest.results ?? []).map {
            (cleanName($0.0) ?? $0.0, $0.1)
        }
        return (name, collectorText(from: numberRequest.results ?? []))
    }

    /// Name OCR that prefers tallest/confident line (title), skips "Evolves from ..." noise.
    private func ocrName(_ image: CIImage,
                         roiPixel: CGRect,
                         hints: [String],
                         autodetect: Bool) -> (String, Float)? {
        guard let (text, conf, _) = ocrTallestLine(image, roiPixel: roiPixel, hints: hints, autodetect: autodetect) else {
            return nil
        }
        let cleaned = cleanName(text) ?? text
        return (cleaned, conf)
    }

    /// Returns joined text + max confidence (for number sweeps).
    private func ocrAll(_ image: CIImage,
                        roiPixel: CGRect,
                        hints: [String],
                        autodetect: Bool,
                        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
                        usesLanguageCorrection: Bool = true,
                        minimumTextHeight: Float = 0.015) -> (String, Float)? {
        let norm = normalize(roiPixel, in: image.extent)
        guard norm.width > 0, norm.height > 0 else { return nil }
        let req = makeRequest(
            hints: hints,
            autodetect: autodetect,
            recognitionLevel: recognitionLevel,
            usesLanguageCorrection: usesLanguageCorrection,
            minimumTextHeight: minimumTextHeight
        )
        req.regionOfInterest = norm
        let h = VNImageRequestHandler(ciImage: image, options: handlerOpts)
        try? h.perform([req])
        let observations = req.results ?? []
        if !usesLanguageCorrection {
            return collectorText(from: observations)
        }
        return joinedText(from: observations)
    }

    /// Crops and enlarges only the footer before OCR. This pass runs only when
    /// the combined fast request did not confidently read a collector number,
    /// keeping the normal path fast while rescuing dim, tiny print.
    private func ocrCollectorNumber(
        _ image: CIImage,
        roiPixel: CGRect,
        hints: [String],
        recognitionLevel: VNRequestTextRecognitionLevel
    ) -> (String, Float)? {
        let extent = image.extent
        let relativeBounds = CGRect(origin: .zero, size: extent.size)
        let relativeCrop = roiPixel.intersection(relativeBounds)
        guard relativeCrop.width > 8, relativeCrop.height > 8 else { return nil }

        let absoluteCrop = CGRect(
            x: extent.minX + relativeCrop.minX,
            y: extent.minY + relativeCrop.minY,
            width: relativeCrop.width,
            height: relativeCrop.height
        )
        var band = image.cropped(to: absoluteCrop)
            .transformed(by: CGAffineTransform(
                translationX: -absoluteCrop.minX,
                y: -absoluteCrop.minY
            ))

        let targetWidth: CGFloat = 960
        let scale = max(1, min(4, targetWidth / max(band.extent.width, 1)))
        if scale > 1 {
            band = band.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        let color = CIFilter.colorControls()
        color.inputImage = band
        color.saturation = 0
        color.brightness = 0.025
        color.contrast = 1.38
        band = color.outputImage ?? band

        let sharp = CIFilter.sharpenLuminance()
        sharp.inputImage = band
        sharp.sharpness = 0.72
        band = sharp.outputImage ?? band

        return ocrAll(
            band,
            roiPixel: CGRect(origin: .zero, size: band.extent.size),
            hints: hints,
            autodetect: false,
            recognitionLevel: recognitionLevel,
            usesLanguageCorrection: false,
            minimumTextHeight: Tune.numberMinimumTextHeight
        )
    }

    /// Pick tallest line (good proxy for card title) with tie-break on confidence.
    private func ocrTallestLine(_ image: CIImage,
                                roiPixel: CGRect,
                                hints: [String],
                                autodetect: Bool) -> (String, Float, CGFloat)? {
        let norm = normalize(roiPixel, in: image.extent)
        guard norm.width > 0, norm.height > 0 else { return nil }
        let req = makeRequest(hints: hints, autodetect: autodetect)
        req.regionOfInterest = norm
        let h = VNImageRequestHandler(ciImage: image, options: handlerOpts)
        try? h.perform([req])

        return bestTitle(from: req.results ?? [])
    }

    private func joinedText(from observations: [VNRecognizedTextObservation]) -> (String, Float)? {
        var joined = ""
        var confidence: Float = 0
        for observation in observations {
            if let candidate = observation.topCandidates(1).first {
                joined += (joined.isEmpty ? "" : "\n") + candidate.string
                confidence = max(confidence, Float(candidate.confidence))
            }
        }
        joined = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : (joined, confidence)
    }

    /// Number OCR often ranks a visually similar O/0 or I/1 reading first.
    /// Inspect a few Vision alternatives and prefer text that has the shape of
    /// a real collector/set identifier before falling back to the top strings.
    private func collectorText(
        from observations: [VNRecognizedTextObservation]
    ) -> (String, Float)? {
        if let joined = joinedText(from: observations), extractNumberRaw(joined.0) != nil {
            return joined
        }

        var best: (String, Float)?
        for observation in observations {
            for candidate in observation.topCandidates(3) {
                guard extractNumberRaw(candidate.string) != nil else { continue }
                let value = (candidate.string, Float(candidate.confidence))
                if value.1 > (best?.1 ?? -1) { best = value }
            }
        }
        return best ?? joinedText(from: observations)
    }

    private func bestTitle(
        from observations: [VNRecognizedTextObservation]
    ) -> (String, Float, CGFloat)? {
        var best: (String, Float, CGFloat)?
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let s = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            if s.isMostlyNumericLike { continue }
            // Skip tiny English template text; avoid stripping JP glyphs.
            if s.range(of: #"(?i)\bevolves\s+from\b"#, options: .regularExpression) != nil { continue }

            let lineH = observation.boundingBox.height // normalized [0,1]
            let conf  = Float(candidate.confidence)
            if let b = best {
                if lineH > b.2 + 0.01 || (abs(lineH - b.2) <= 0.01 && conf > b.1) {
                    best = (s, conf, lineH)
                }
            } else {
                best = (s, conf, lineH)
            }
        }
        return best
    }

    private func makeRequest(
        hints: [String],
        autodetect: Bool,
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        usesLanguageCorrection: Bool = true,
        minimumTextHeight: Float = 0.015
    ) -> VNRecognizeTextRequest {
        let r = VNRecognizeTextRequest(completionHandler: nil)
        r.recognitionLevel = recognitionLevel
        r.usesLanguageCorrection = usesLanguageCorrection
        r.minimumTextHeight = minimumTextHeight
        if #available(iOS 16.0, *) {
            r.automaticallyDetectsLanguage = autodetect
            r.customWords = ocrCustomWords
        }
        // Keep only language models available at this recognition level on the
        // current device. This prevents one unsupported locale from failing the
        // whole multilingual OCR request.
        let requested = hints.isEmpty ? mixedHints : hints
        if let supported = try? r.supportedRecognitionLanguages() {
            let filtered = requested.filter(supported.contains)
            r.recognitionLanguages = filtered.isEmpty ? Array(supported.prefix(1)) : filtered
        } else {
            r.recognitionLanguages = requested
        }
        return r
    }

    // MARK: - Text cleanup & numbers

    private func cleanName(_ s: String?) -> String? {
        guard var t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        // Remove obvious EN UI tokens without harming JP text
        t = t.replacingOccurrences(of: #"(?i)\b(BASIC|STAGE\s*[12]|RESTORED)\b"#,
                                   with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?i)HP\s*\d{2,3}"#,
                                   with: "", options: .regularExpression)
        if game == .pokemon {
            // Preserve every printed Pokémon title modifier. Vision sometimes
            // inserts spaces or substitutes a dash, so canonicalize only the
            // suffix spelling used to query the card catalogues.
            t = t.replacingOccurrences(of: #"(?i)\bV\s*STAR\b"#,
                                       with: "VSTAR", options: .regularExpression)
            t = t.replacingOccurrences(of: #"(?i)\bV\s*MAX\b"#,
                                       with: "VMAX", options: .regularExpression)
            t = t.replacingOccurrences(of: #"(?i)\bV\s*[-‐‑–—]?\s*UNION\b"#,
                                       with: "V-UNION", options: .regularExpression)
            t = t.replacingOccurrences(of: #"(?i)\bLV\s*\.?\s*X\b"#,
                                       with: "LV.X", options: .regularExpression)
            t = t.replacingOccurrences(of: #"(?i)\bTAG\s+TEAM\b"#,
                                       with: "TAG TEAM", options: .regularExpression)
        }
        // Normalize whitespace
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func extractNumberRaw(_ s: String?) -> String? {
        guard let s = s, !s.isEmpty else { return nil }

        // On very small footer text, Vision commonly confuses 0/O, 1/I/L, or
        // the fraction slash with a vertical bar. Repair only an all-numeric
        // fraction shape so card names and alphanumeric set codes stay intact.
        if let range = s.range(
            of: #"(?i)\b[0-9OIL]{1,4}\s*[/|\\]\s*[0-9OIL]{1,4}\b"#,
            options: .regularExpression
        ) {
            let repaired = String(s[range])
                .uppercased()
                .replacingOccurrences(of: "O", with: "0")
                .replacingOccurrences(of: "I", with: "1")
                .replacingOccurrences(of: "L", with: "1")
                .replacingOccurrences(of: "|", with: "/")
                .replacingOccurrences(of: "\\", with: "/")
                .replacingOccurrences(of: " ", with: "")
            if repaired.range(
                of: #"^\d{1,4}/\d{1,4}$"#,
                options: .regularExpression
            ) != nil {
                return repaired
            }
        }

        let patterns = [
            #"(?i)\b[A-Z]{0,4}\d{1,4}\s*/\s*[A-Z]{0,4}\d{1,4}\b"#,            // 096/165, TG01/TG30
            #"(?i)\b[A-Z0-9]{2,8}-(?:EN|JP|ES|FR|DE|IT|PT|KO|ZH)?\d{1,4}\b"#,   // LOB-001, RA02-EN001
            #"(?i)\bS?V?P?[- ]?(EN|JP|ES|FR|DE|IT|PT|KO|ZH)\s*-?\s*\d{1,4}\b"#, // SVP-EN123
            #"(?i)\bSWSH\s*\d{1,4}\b"#,
            #"(?i)\b(?:SM|XY|SV|TG|GG|RC|SH)\s*\d{1,4}\b"#,
            #"(?i)\bNo\.?\s*\d{1,4}\b"#
        ]
        for p in patterns {
            if let r = s.range(of: p, options: .regularExpression) {
                return String(s[r]).trimmingCharacters(in: .whitespaces)
            }
        }
        if game == .magic {
            return firstMagicCollectorNumber(in: s)
        }
        return nil
    }

    private func firstMagicCollectorNumber(in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: #"(?i)\b\d{1,4}[a-z]?\b"#) else {
            return nil
        }
        let fullRange = NSRange(text.startIndex..., in: text)
        for match in expression.matches(in: text, range: fullRange) {
            guard let range = Range(match.range, in: text) else { continue }
            let token = String(text[range])
            let digits = token.replacingOccurrences(of: #"\D"#, with: "", options: .regularExpression)
            if let numeric = Int(digits), (1900...2099).contains(numeric) { continue }
            return token
        }
        return nil
    }

    private func stripLeadingZeros(_ s: String) -> String {
        let noZeros = s.replacingOccurrences(of: "^0+(?=\\d)", with: "", options: .regularExpression)
        return noZeros.isEmpty ? "0" : noZeros
    }

    private func reduceLeftNumber(_ raw: String?) -> String? {
        guard var raw = raw else { return nil }
        raw = raw.replacingOccurrences(of: " ", with: "")

        // 1) fraction like 096/165 or TG01/TG30 → take the printed left part
        if raw.range(of: #"(?i)^[A-Z]{0,4}\d{1,4}/[A-Z]{0,4}\d{1,4}$"#, options: .regularExpression) != nil {
            let left = raw.split(separator: "/").first.map { String($0) } ?? ""
            return normalizePrefixedNumber(left)
        }

        // 2) No. 0123 → digits only
        if let r = raw.range(of: #"^No\.?\s*\d{1,4}$"#, options: .regularExpression) {
            let digits = raw[r]
                .replacingOccurrences(of: "No.", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "\\D", with: "", options: .regularExpression)
            return stripLeadingZeros(digits)
        }

        // 3) Yu-Gi-Oh! set codes are exact print identifiers; preserve them.
        if raw.range(of: #"(?i)^[A-Z0-9]{2,8}-(?:EN|JP|ES|FR|DE|IT|PT|KO|ZH)?\d{1,4}$"#, options: .regularExpression) != nil {
            return raw.uppercased()
        }

        // 4) Pokémon promo/code → keep the meaningful prefix and number.
        if let r = raw.range(of: #"S(WSH|V|VP)?[- ]?(EN|JP|ES|FR|DE|IT|PT|KO|ZH)-?\d{1,4}"#, options: .regularExpression) {
            let str = String(raw[r])
            return str.replacingOccurrences(of: " ", with: "").uppercased()
        }
        if let r = raw.range(of: #"(?i)(?:SM|XY|SV|TG|GG|RC|SH)\s*\d{1,4}"#, options: .regularExpression) {
            return normalizePrefixedNumber(String(raw[r]))
        }

        // 5) Magic collector numbers can contain a printing suffix (123a).
        if game == .magic,
           raw.range(of: #"(?i)^\d{1,4}[a-z]?$"#, options: .regularExpression) != nil {
            let suffix = raw.last?.isLetter == true ? String(raw.suffix(1)).lowercased() : ""
            let digits = raw.replacingOccurrences(of: #"\D"#, with: "", options: .regularExpression)
            return stripLeadingZeros(digits) + suffix
        }

        // 6) Fallback first numeric token
        if let m = raw.range(of: #"\b\d{1,4}\b"#, options: .regularExpression) {
            return stripLeadingZeros(String(raw[m]))
        }
        return nil
    }

    private func normalizePrefixedNumber(_ value: String) -> String {
        let compact = value.replacingOccurrences(of: " ", with: "").uppercased()
        guard let digits = compact.range(of: #"\d{1,4}$"#, options: .regularExpression) else {
            return compact
        }
        let prefix = String(compact[..<digits.lowerBound])
        let number = String(compact[digits])
        return prefix.isEmpty ? stripLeadingZeros(number) : prefix + number
    }

    // MARK: - Geometry

    private func rectIsUsable(_ r: CGRect) -> Bool {
        r.origin.x.isFinite && r.origin.y.isFinite &&
        r.width.isFinite && r.height.isFinite &&
        r.width > 8 && r.height > 8
    }

    private func normalize(_ roi: CGRect, in extent: CGRect) -> CGRect {
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else {
            return .zero
        }
        let x = max(0, min(1, roi.origin.x / extent.width))
        let y = max(0, min(1, roi.origin.y / extent.height))
        let w = max(0, min(1, roi.width  / extent.width))
        let h = max(0, min(1, roi.height / extent.height))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func inflate(_ r: CGRect, w: CGFloat, h: CGFloat, dx: CGFloat, dy: CGFloat) -> CGRect {
        let x = max(0, r.minX - dx * w)
        let y = max(0, r.minY - dy * h)
        let W = max(0.0, min(w, r.maxX + dx * w) - x)
        let H = max(0.0, min(h, r.maxY + dy * h) - y)
        return CGRect(x: x, y: y, width: W, height: H)
    }

    private func perspectiveCorrect(_ image: CIImage, rect: VNRectangleObservation) -> CIImage {
        let pts = [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]
        guard pts.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return image }
        let f = CIFilter.perspectiveCorrection()
        f.inputImage = image
        func pt(_ n: CGPoint) -> CGPoint {
            CGPoint(x: n.x * image.extent.width, y: n.y * image.extent.height)
        }
        f.topLeft     = pt(rect.topLeft)
        f.topRight    = pt(rect.topRight)
        f.bottomLeft  = pt(rect.bottomLeft)
        f.bottomRight = pt(rect.bottomRight)
        return f.outputImage ?? image
    }

    private func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard inter.width > 0, inter.height > 0 else { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        return interArea / max(unionArea, 1e-6)
    }

    private func centerFallback(_ image: CIImage) -> CIImage {
        let W = image.extent.width
        let H = image.extent.height
        guard W.isFinite, H.isFinite, W > 0, H > 0 else { return image }
        let w = max(32, W * 0.62)
        let h = max(32, min(H * 0.85, w / 0.72))
        let x = max(0, (W - w) / 2)
        let y = max(0, (H - h) / 2)
        let crop = CGRect(x: x, y: y, width: min(w, W - x), height: min(h, H - y))
        if crop.width <= 0 || crop.height <= 0 { return image }
        return image.cropped(to: crop)
    }

    // MARK: - Preprocess

    private func preprocess(_ img: CIImage) -> CIImage {
        var image = img
        let opts: [CIImageAutoAdjustmentOption: Any] = [.enhance: true]
        for f in image.autoAdjustmentFilters(options: opts) {
            f.setValue(image, forKey: kCIInputImageKey)
            image = f.outputImage ?? image
        }
        let color = CIFilter.colorControls()
        color.inputImage = image
        color.saturation = 0.0
        color.contrast = 1.18
        image = color.outputImage ?? image

        let sharp = CIFilter.sharpenLuminance()
        sharp.inputImage = image
        sharp.sharpness = 0.45
        image = sharp.outputImage ?? image

        let denoise = CIFilter.noiseReduction()
        denoise.inputImage = image
        denoise.noiseLevel = 0.02
        denoise.sharpness = 0.4
        return denoise.outputImage ?? image
    }
}
