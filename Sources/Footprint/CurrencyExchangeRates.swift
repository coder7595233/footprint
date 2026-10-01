import Foundation

struct CurrencyExchangeRateDay: Codable, Hashable, Sendable {
    var date: String
    var rates: [String: Double]

    mutating func normalize() {
        date = DateParsers.canonicalizedDayInput(date).trimmingCharacters(in: .whitespacesAndNewlines)
        rates = Dictionary(firstWinsKeysWithValues: rates.compactMap { key, value in
            let code = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !code.isEmpty, value > 0 else { return nil }
            return (code, value)
        })
        rates["EUR"] = 1
    }
}

struct CurrencyConversionQuote: Hashable, Sendable {
    var currency: String
    var requestedDate: String
    var rateDate: String
    var factorToSEK: Double

    func convertingToSEK(_ value: Double) -> Double {
        value * factorToSEK
    }
}

struct CurrencyExchangeRateCache: Codable, Hashable, Sendable {
    var sourceURL: String
    var fetchedAt: String
    var firstApplicationDate: String?
    var days: [CurrencyExchangeRateDay]

    static let ecbHistoricalXMLURLString = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml"

    static var empty: CurrencyExchangeRateCache {
        CurrencyExchangeRateCache(
            sourceURL: ecbHistoricalXMLURLString,
            fetchedAt: "",
            firstApplicationDate: nil,
            days: []
        )
    }

    mutating func normalize() {
        sourceURL = sourceURL.trimmedOrNil ?? Self.ecbHistoricalXMLURLString
        fetchedAt = DateParsers.canonicalizedDayInput(fetchedAt).trimmingCharacters(in: .whitespacesAndNewlines)
        firstApplicationDate = firstApplicationDate.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
        days = days.map { day in
            var normalized = day
            normalized.normalize()
            return normalized
        }
        .filter { $0.date.trimmedOrNil != nil && $0.rates["SEK"] != nil }
        .uniquedBy(\.date)
        .sorted { $0.date > $1.date }
    }

    var fetchedDate: Date? {
        DateParsers.isoDay.date(from: fetchedAt)
    }

    var newestDate: String? {
        days.first?.date
    }

    var oldestDate: String? {
        days.last?.date
    }

    func hasRate(for currency: String, onOrBefore date: String) -> Bool {
        conversionFactorToSEK(for: currency, onOrBefore: date) != nil
    }

    func conversionFactorToSEK(for currency: String?, onOrBefore date: String) -> Double? {
        conversionQuoteToSEK(for: currency, onOrBefore: date)?.factorToSEK
    }

    func conversionQuoteToSEK(for currency: String?, onOrBefore date: String) -> CurrencyConversionQuote? {
        let code = normalizedCurrencyCode(currency)
        let targetDate = DateParsers.canonicalizedDayInput(date).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetDate.isEmpty else { return nil }
        if code == "SEK" {
            return CurrencyConversionQuote(
                currency: code,
                requestedDate: targetDate,
                rateDate: targetDate,
                factorToSEK: 1
            )
        }

        for day in days where day.date <= targetDate {
            guard let sekPerEuro = day.rates["SEK"], sekPerEuro > 0 else { continue }
            if code == "EUR" {
                return CurrencyConversionQuote(
                    currency: code,
                    requestedDate: targetDate,
                    rateDate: day.date,
                    factorToSEK: sekPerEuro
                )
            }
            guard let unitsPerEuro = day.rates[code], unitsPerEuro > 0 else { continue }
            return CurrencyConversionQuote(
                currency: code,
                requestedDate: targetDate,
                rateDate: day.date,
                factorToSEK: sekPerEuro / unitsPerEuro
            )
        }
        return nil
    }

    func convertingToSEK(_ value: Double?, currency: String?, onOrBefore date: String) -> Double? {
        guard let value else { return nil }
        guard let factor = conversionFactorToSEK(for: currency, onOrBefore: date) else { return nil }
        return value * factor
    }

    static func parsedECBHistoricalXML(_ data: Data, firstApplicationDate: String?, fetchedAt: Date = Date()) throws -> CurrencyExchangeRateCache {
        let parser = XMLParser(data: data)
        let delegate = ECBHistoricalRatesXMLParserDelegate(firstApplicationDate: firstApplicationDate)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? CurrencyExchangeRateError.invalidXML
        }
        var cache = CurrencyExchangeRateCache(
            sourceURL: ecbHistoricalXMLURLString,
            fetchedAt: DateParsers.isoDay.string(from: fetchedAt),
            firstApplicationDate: firstApplicationDate,
            days: delegate.days
        )
        cache.normalize()
        return cache
    }
}

enum CurrencyExchangeRateError: LocalizedError {
    case invalidXML
    case noHistoricalRates

    var errorDescription: String? {
        switch self {
        case .invalidXML:
            return "Could not parse ECB exchange-rate XML."
        case .noHistoricalRates:
            return "ECB exchange-rate XML did not contain usable historical rates."
        }
    }
}

private final class ECBHistoricalRatesXMLParserDelegate: NSObject, XMLParserDelegate {
    private let firstApplicationDate: String?
    private var cubeDepth = 0
    private var activeDayDepth: Int?
    private var activeDate: String?
    private var activeRates: [String: Double] = [:]

    private(set) var days: [CurrencyExchangeRateDay] = []

    init(firstApplicationDate: String?) {
        self.firstApplicationDate = firstApplicationDate.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.hasSuffix("Cube") else { return }
        cubeDepth += 1

        if let time = attributeDict["time"].map(DateParsers.canonicalizedDayInput)?.trimmedOrNil {
            activeDayDepth = cubeDepth
            activeDate = time
            activeRates = ["EUR": 1]
            return
        }

        guard activeDate != nil,
              let currency = attributeDict["currency"]?.trimmedOrNil?.uppercased(),
              let rawRate = attributeDict["rate"]?.trimmedOrNil,
              let rate = Double(rawRate),
              rate > 0 else {
            return
        }
        activeRates[currency] = rate
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.hasSuffix("Cube") else { return }
        defer { cubeDepth = max(0, cubeDepth - 1) }

        guard activeDayDepth == cubeDepth,
              let date = activeDate else {
            return
        }

        defer {
            activeDayDepth = nil
            activeDate = nil
            activeRates = [:]
        }

        if let firstApplicationDate, date < firstApplicationDate {
            return
        }
        guard activeRates["SEK"] != nil else { return }
        days.append(CurrencyExchangeRateDay(date: date, rates: activeRates))
    }
}

private func normalizedCurrencyCode(_ currency: String?) -> String {
    currency?.trimmedOrNil?.uppercased() ?? "SEK"
}

private struct CurrencyConversionRequirement: Hashable {
    let currency: String
    let date: String
}

extension GrantApplication {
    var currencyCode: String {
        normalizedCurrencyCode(currency)
    }

    func currencyConversionReferenceDateString(today: Date = Date()) -> String {
        let status = resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if status == "Beviljat" || status == "Avslag" {
            if let decision = decisionDate {
                return DateParsers.isoDay.string(from: decision)
            }
            if let decision = resolvedDecisionDateString?.trimmedOrNil {
                return DateParsers.canonicalizedDayInput(decision)
            }
        }
        return DateParsers.isoDay.string(from: today)
    }
}

extension GrantDataStore {
    nonisolated static let currencyExchangeRatesStorageKey = "currency_exchange_rates"

    nonisolated static var currencyExchangeRatesURL: URL {
        storageDirectory.appendingPathComponent("currency_exchange_rates.json")
    }

    nonisolated static func loadCurrencyExchangeRateCache(
        from sqliteStore: SQLiteDocumentStore? = nil
    ) -> CurrencyExchangeRateCache {
        if let sqliteStore,
           let cache = try? sqliteStore.load(
               CurrencyExchangeRateCache.self,
               named: currencyExchangeRatesStorageKey
           ) {
            var normalized = cache
            normalized.normalize()
            return normalized
        }

        guard FileManager.default.fileExists(atPath: currencyExchangeRatesURL.path),
              let cache = try? decode(CurrencyExchangeRateCache.self, from: currencyExchangeRatesURL) else {
            return .empty
        }
        var normalized = cache
        normalized.normalize()
        try? sqliteStore?.save(normalized, named: currencyExchangeRatesStorageKey)
        return normalized
    }

    /// Dedicated session for the ECB fetch: explicit request/resource
    /// timeouts instead of the shared session's defaults, so a stalled
    /// download cannot hold the refresh task for minutes.
    nonisolated private static let currencyExchangeRateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()

    /// The full ECB history file is a few MB; anything past this ceiling is
    /// not the expected document and must not be buffered or parsed.
    nonisolated private static let currencyExchangeRateMaximumResponseBytes = 64 * 1024 * 1024

    func refreshCurrencyExchangeRatesIfNeeded(force: Bool = false) {
        let firstApplicationDate = Self.firstCurrencyRelevantApplicationDate(in: applications)
        let requirements = Self.currencyConversionRequirements(for: applications)
        guard !requirements.isEmpty else { return }
        guard force || shouldRefreshCurrencyExchangeRateCache(requirements: requirements, firstApplicationDate: firstApplicationDate) else {
            return
        }
        guard currencyExchangeRateRefreshTask == nil else { return }

        currencyExchangeRateRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.currencyExchangeRateRefreshTask = nil }
            guard let url = URL(string: CurrencyExchangeRateCache.ecbHistoricalXMLURLString) else { return }

            do {
                let (data, response) = try await Self.currencyExchangeRateSession.data(from: url)
                let declaredLength = response.expectedContentLength
                guard declaredLength <= Int64(Self.currencyExchangeRateMaximumResponseBytes),
                      data.count <= Self.currencyExchangeRateMaximumResponseBytes else {
                    throw CurrencyExchangeRateError.noHistoricalRates
                }
                let cache = try await Task.detached(priority: .utility) {
                    try CurrencyExchangeRateCache.parsedECBHistoricalXML(
                        data,
                        firstApplicationDate: firstApplicationDate,
                        fetchedAt: Date()
                    )
                }.value
                guard !cache.days.isEmpty else { throw CurrencyExchangeRateError.noHistoricalRates }
                currencyExchangeRateCache = cache
                try persistCurrencyExchangeRateCache(cache)
            } catch {
                appendStartupDiagnostic("currency exchange-rate refresh failed error=\(error.localizedDescription)")
                presentStaleCurrencyRatesNoticeIfNeeded()
            }
        }
    }

    /// A failed rate refresh used to be completely silent while SEK
    /// approximations in reports quietly kept using old rates. Shown at most
    /// once per app run, and only when the cached rates are old or missing.
    private func presentStaleCurrencyRatesNoticeIfNeeded() {
        guard !didNotifyStaleCurrencyRates else { return }
        let latestDay = currencyExchangeRateCache.days.map(\.date).max()
        if let latestDay,
           let parsed = DateParsers.isoDay.date(from: latestDay),
           Date().timeIntervalSince(parsed) < 30 * 24 * 3600 {
            return
        }
        didNotifyStaleCurrencyRates = true
        let detail = latestDay.map {
            language.text(
                "Amounts in foreign currency use rates from \($0).",
                "Belopp i utländsk valuta använder kurser från \($0)."
            )
        } ?? language.text(
            "Amounts in foreign currency cannot be converted to SEK.",
            "Belopp i utländsk valuta kan inte räknas om till SEK."
        )
        notice = StoreNotice(
            message: language.text(
                "Could not update exchange rates.",
                "Kunde inte uppdatera valutakurser."
            ) + " " + detail,
            tone: .info
        )
    }

    func approximateSEKValue(_ value: Double?, for application: GrantApplication) -> Double? {
        guard let value else { return nil }
        let date = application.currencyConversionReferenceDateString()
        return currencyExchangeRateCache.convertingToSEK(value, currency: application.currency, onOrBefore: date)
    }

    /// Amount in SEK for sums and statistics. A foreign amount without an
    /// exchange rate counts as 0 (it used to be added as if it were
    /// kronor); sums show it separately as "ej omräknat" through
    /// `unconvertedAmountSuffix(for:)`.
    func grantStatisticsAmountInSEK(for application: GrantApplication, amount: Double?) -> Double {
        guard let amount else { return 0 }
        if application.currencyCode == "SEK" { return amount }
        return approximateSEKValue(amount, for: application) ?? 0
    }

    func isGrantAmountUnconverted(for application: GrantApplication, amount: Double?) -> Bool {
        guard let amount, amount != 0, application.currencyCode != "SEK" else { return false }
        return approximateSEKValue(amount, for: application) == nil
    }

    /// " (ej omräknat: 1 000 USD)" for the amounts in `rows` that could not be
    /// converted to SEK, or "" when every amount was converted.
    func unconvertedAmountSuffix(for rows: [(application: GrantApplication, amount: Double?)]) -> String {
        let text = unconvertedAmountText(for: rows)
        return text.isEmpty ? "" : " (\(text))"
    }

    func unconvertedAmountText(for rows: [(application: GrantApplication, amount: Double?)]) -> String {
        var byCurrency: [String: Double] = [:]
        for row in rows where isGrantAmountUnconverted(for: row.application, amount: row.amount) {
            byCurrency[row.application.currencyCode, default: 0] += row.amount ?? 0
        }
        guard !byCurrency.isEmpty else { return "" }
        let amounts = byCurrency.keys.sorted().map { CurrencyFormatter.format(byCurrency[$0], code: $0) }
        return language.text("not converted", "ej omräknat") + ": " + amounts.joined(separator: " • ")
    }

    func formattedGrantAmountWithSEKApproximation(_ value: Double?, for application: GrantApplication) -> String {
        let original = CurrencyFormatter.format(value, code: application.currency)
        guard value != nil,
              application.currencyCode != "SEK",
              let approximateSEK = approximateSEKValue(value, for: application) else {
            return original
        }
        return "\(original) (≈ \(CurrencyFormatter.format(approximateSEK, code: "SEK")))"
    }

    func formattedApproximateSEKAmount(_ value: Double?, for application: GrantApplication) -> String {
        guard let value else { return "N/A" }
        if application.currencyCode == "SEK" {
            return CurrencyFormatter.format(value, code: "SEK")
        }
        guard let approximateSEK = approximateSEKValue(value, for: application) else {
            return CurrencyFormatter.format(value, code: application.currency)
        }
        return "≈ \(CurrencyFormatter.format(approximateSEK, code: "SEK"))"
    }

    func currencyConversionHelpText(
        for value: Double?,
        application: GrantApplication,
        language: AppLanguage
    ) -> String? {
        let code = application.currencyCode
        guard code != "SEK" else { return nil }
        let referenceDate = application.currencyConversionReferenceDateString()
        guard let value else {
            return language.text(
                "Enter an amount to show the approximate SEK conversion.",
                "Ange ett belopp för att visa ungefärlig omräkning till SEK."
            )
        }
        guard let quote = currencyExchangeRateCache.conversionQuoteToSEK(for: code, onOrBefore: referenceDate) else {
            return language.text(
                "No ECB exchange rate was found for \(code) on or before \(referenceDate).",
                "Ingen ECB-kurs hittades för \(code) på eller före \(referenceDate)."
            )
        }

        let rate = formattedExchangeRateFactor(quote.factorToSEK, language: language)
        let total = CurrencyFormatter.format(quote.convertingToSEK(value), code: "SEK")
        if language == .swedish {
            return """
            Valutakurs: 1 \(code) ≈ \(rate) SEK
            Kursdatum: \(quote.rateDate)
            Omräknat sökt belopp: ≈ \(total)
            """
        }
        return """
        Exchange rate: 1 \(code) ≈ \(rate) SEK
        Rate date: \(quote.rateDate)
        Converted applied amount: ≈ \(total)
        """
    }

    func formattedGrantAmountSummaryInSEK(
        for applications: [GrantApplication],
        value keyPath: KeyPath<GrantApplication, Double?>
    ) -> String {
        let rows = applications.compactMap { application -> (application: GrantApplication, amount: Double)? in
            guard let amount = application[keyPath: keyPath] else { return nil }
            return (application, amount)
        }
        guard !rows.isEmpty else { return "—" }

        var total = 0.0
        var hasConvertedCurrency = false
        var unconvertedRows: [(application: GrantApplication, amount: Double)] = []
        for row in rows {
            if row.application.currencyCode == "SEK" {
                total += row.amount
            } else if let converted = approximateSEKValue(row.amount, for: row.application) {
                total += converted
                hasConvertedCurrency = true
            } else {
                unconvertedRows.append(row)
            }
        }
        if unconvertedRows.count == rows.count {
            return formattedOriginalCurrencySummary(rows) + " (" + language.text("not converted", "ej omräknat") + ")"
        }

        let formatted = CurrencyFormatter.format(total, code: "SEK")
        let suffix = unconvertedAmountSuffix(for: unconvertedRows.map { ($0.application, Optional($0.amount)) })
        return (hasConvertedCurrency ? "≈ \(formatted)" : formatted) + suffix
    }

    private func formattedOriginalCurrencySummary(_ rows: [(application: GrantApplication, amount: Double)]) -> String {
        let grouped = Dictionary(grouping: rows, by: { $0.application.currencyCode })
        return grouped.keys.sorted().map { currency in
            CurrencyFormatter.format(grouped[currency]?.map(\.amount).reduce(0, +), code: currency)
        }
        .joined(separator: " • ")
    }

    private func shouldRefreshCurrencyExchangeRateCache(
        requirements: Set<CurrencyConversionRequirement>,
        firstApplicationDate: String?
    ) -> Bool {
        let cache = currencyExchangeRateCache
        guard !cache.days.isEmpty else { return true }

        // The ECB reference series starts 1999-01-04. Requirements before
        // that can never be satisfied; comparing against them made every
        // application edit re-download the full history.
        let ecbEpoch = "1999-01-04"
        if let firstApplicationDate,
           let oldest = cache.oldestDate,
           oldest > max(firstApplicationDate, ecbEpoch) {
            return true
        }

        if let fetchedDate = cache.fetchedDate,
           let staleAfter = Calendar(identifier: .gregorian).date(byAdding: .day, value: 7, to: fetchedDate),
           staleAfter > Date() {
            // A fresh cache already holds the full history; refetching can
            // only add days newer than the newest cached one. Anything
            // still missing below that is unfixable by another download.
            let missingRequirement = requirements.contains { requirement in
                requirement.date >= ecbEpoch
                    && (cache.newestDate.map { requirement.date > $0 } ?? true)
                    && !cache.hasRate(for: requirement.currency, onOrBefore: requirement.date)
            }
            return missingRequirement
        }

        return true
    }

    private func persistCurrencyExchangeRateCache(_ cache: CurrencyExchangeRateCache) throws {
        guard let sqliteStore else {
            throw NSError(domain: "Footprint", code: 67, userInfo: [
                NSLocalizedDescriptionKey: "SQLite storage is required for currency exchange-rate cache.",
            ])
        }
        try sqliteStore.save(cache, named: Self.currencyExchangeRatesStorageKey)
    }

    private nonisolated static func firstCurrencyRelevantApplicationDate(in applications: [GrantApplication]) -> String? {
        applications
            .compactMap { application -> String? in
                [
                    application.appliedOn,
                    application.closesOn,
                    application.resolvedDecisionDateString,
                    application.decisionExpectedOn,
                ]
                .compactMap { $0.map(DateParsers.canonicalizedDayInput)?.trimmedOrNil }
                .min()
            }
            .min()
    }

    private nonisolated static func currencyConversionRequirements(for applications: [GrantApplication], today: Date = Date()) -> Set<CurrencyConversionRequirement> {
        Set(
            applications.compactMap { application -> CurrencyConversionRequirement? in
                let code = application.currencyCode
                guard code != "SEK" else { return nil }
                guard application.preferredBudgetAmountValue != nil ||
                    application.appliedAmountValue != nil ||
                    application.grantedAmountValue != nil ||
                    application.receivedConsumedAmountValue != nil else {
                    return nil
                }
                return CurrencyConversionRequirement(
                    currency: code,
                    date: application.currencyConversionReferenceDateString(today: today)
                )
            }
        )
    }
}

private func formattedExchangeRateFactor(_ value: Double, language: AppLanguage) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: language == .swedish ? "sv_SE" : "en_US")
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 4
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.4f", value)
}

private extension Array {
    func uniquedBy<Value: Hashable>(_ keyPath: KeyPath<Element, Value>) -> [Element] {
        var seen = Set<Value>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
