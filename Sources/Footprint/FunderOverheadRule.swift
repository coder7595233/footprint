import Foundation

// MARK: - OH rule per grant provider (round 8)
//
// Swedish research funding: the overhead (OH) of an application depends on
// both the fund manager (its own full OH) and the grant provider (which may
// accept the fund manager's full OH, cap it, or give none). Everything is set
// by the user on the organizations; nothing is chosen by name.

/// The three choices of "OH-regel" on a grant provider.
enum FunderOverheadRuleKind: String, Codable, Hashable, CaseIterable {
    /// "Förvaltarens fulla OH": the fund manager's own OH is accepted.
    case managerFull
    /// "Högst __ %": at most `capPercent`, never more than the fund manager's OH.
    case cap
    /// "Ingen OH": the grant provider gives no overhead. Stored as "none".
    /// (Not named `none`, so it is never mixed up with an empty optional.)
    case noOverhead = "none"
}

/// "OH-regel" on a grant provider (or in an exception for one fund manager).
struct FunderOverheadRule: Codable, Hashable {
    var kind: FunderOverheadRuleKind
    /// The cap for `.cap`, in percent (0–100). Kept when another choice is
    /// picked so the number is still there if "Högst" is chosen again; it
    /// only counts for `.cap`.
    var capPercent: Double?
    /// "Taket inkluderar lokalkostnad": a note on the cap. The app does not
    /// count premises costs separately, so it does not change the numbers.
    var capIncludesPremises: Bool

    enum CodingKeys: String, CodingKey {
        case kind
        case capPercent
        case capIncludesPremises
    }

    init(kind: FunderOverheadRuleKind = .managerFull, capPercent: Double? = nil, capIncludesPremises: Bool = false) {
        self.kind = kind
        self.capPercent = capPercent
        self.capIncludesPremises = capIncludesPremises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decodeIfPresent(String.self, forKey: .kind)
        self.init(
            kind: rawKind.flatMap(FunderOverheadRuleKind.init(rawValue:)) ?? .managerFull,
            capPercent: try container.decodeIfPresent(Double.self, forKey: .capPercent),
            capIncludesPremises: try container.decodeIfPresent(Bool.self, forKey: .capIncludesPremises) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encodeIfPresent(capPercent, forKey: .capPercent)
        if capIncludesPremises {
            try container.encode(true, forKey: .capIncludesPremises)
        }
    }

    /// The standard choice: the fund manager's full OH, no cap.
    var isStandard: Bool {
        self == FunderOverheadRule()
    }

    /// The cap in percent kept between 0 and 100.
    func normalized() -> FunderOverheadRule {
        var copy = self
        copy.capPercent = capPercent.map { min(100, max(0, $0)) }
        return copy
    }

    /// The grant provider's cap as shown in the application ("anslagsgivarens
    /// tak"): the percent for "Högst", 0 for "Ingen OH", nil when there is no
    /// cap (the fund manager's full OH, or "Högst" without a number).
    var effectiveCapPercent: Double? {
        switch kind {
        case .managerFull:
            return nil
        case .cap:
            return capPercent.map { min(100, max(0, $0)) }
        case .noOverhead:
            return 0
        }
    }

    /// The OH rate that counts (a fraction, 0.2 = 20 %) when the fund
    /// manager's own rate is `managerRate`: the full rate, the lower of the
    /// rate and the cap, or nothing. A cap above the fund manager's OH gives
    /// the fund manager's OH.
    func effectiveRate(managerRate: Double) -> Double {
        let rate = max(0, managerRate)
        switch kind {
        case .managerFull:
            return rate
        case .cap:
            return grantOverheadRate(rate, cappedAtPercent: effectiveCapPercent)
        case .noOverhead:
            return 0
        }
    }

    /// Round 8, one-time move of the earlier setting "Max OH (%)": no value
    /// gives no rule (the standard), 0 gives "Ingen OH" and any other value
    /// "Högst value %".
    static func migrated(fromLegacyMaxOverheadPercent percent: Double?) -> FunderOverheadRule? {
        guard let percent else { return nil }
        let clamped = min(100, max(0, percent))
        if clamped == 0 {
            return FunderOverheadRule(kind: .noOverhead)
        }
        return FunderOverheadRule(kind: .cap, capPercent: clamped)
    }
}

/// "När [medelsförvaltare] förvaltar: …": an exception on a grant provider
/// for one fund manager, found by the fund manager organization's id.
struct FunderOverheadRuleException: Codable, Hashable, Identifiable {
    var id: String
    var managerOrganizationID: String
    var rule: FunderOverheadRule

    enum CodingKeys: String, CodingKey {
        case id
        case managerOrganizationID
        case rule
    }

    init(id: String = UUID().uuidString, managerOrganizationID: String, rule: FunderOverheadRule = FunderOverheadRule()) {
        self.id = id
        self.managerOrganizationID = managerOrganizationID
        self.rule = rule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            managerOrganizationID: try container.decodeIfPresent(String.self, forKey: .managerOrganizationID) ?? "",
            rule: try container.decodeIfPresent(FunderOverheadRule.self, forKey: .rule) ?? FunderOverheadRule()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(managerOrganizationID, forKey: .managerOrganizationID)
        try container.encode(rule, forKey: .rule)
    }
}

extension OrganizationRecord {
    /// The OH rule of this grant provider for applications managed by the
    /// fund manager with the given organization id: that fund manager's
    /// exception when there is one, otherwise the provider's own rule
    /// (standard: the fund manager's full OH).
    func resolvedOverheadRule(forManagerOrganizationID managerOrganizationID: String?) -> FunderOverheadRule {
        if let managerID = managerOrganizationID?.trimmingCharacters(in: .whitespacesAndNewlines), !managerID.isEmpty,
           let exception = (overheadRuleExceptions ?? []).first(where: { $0.managerOrganizationID == managerID }) {
            return exception.rule
        }
        return overheadRule ?? FunderOverheadRule()
    }
}

/// How the OH of an application's salary budget is found: the grant
/// provider's rule (already resolved for the application's fund manager)
/// and the fund manager's own full OH.
struct GrantOverheadPlan: Equatable {
    var rule: FunderOverheadRule
    /// The fund manager's OH per period (its salary calculator). Used when
    /// at least one period is filled in.
    var managerOverheadPeriods: [SalaryCalculatorPeriod]
    /// "Förvaltarens fulla OH (%)" on the fund manager, used when it has no
    /// OH periods. When neither exists, the OH periods of the salary
    /// calculator used for applications count (as before).
    var managerOverheadPercent: Double?

    init(
        rule: FunderOverheadRule = FunderOverheadRule(),
        managerOverheadPeriods: [SalaryCalculatorPeriod] = [],
        managerOverheadPercent: Double? = nil
    ) {
        self.rule = rule
        self.managerOverheadPeriods = managerOverheadPeriods
        self.managerOverheadPercent = managerOverheadPercent
    }

    /// The earlier single setting "Max OH (%)" (nil = no cap, 0 = no OH).
    init(legacyMaxOverheadPercent: Double?) {
        self.init(rule: FunderOverheadRule.migrated(fromLegacyMaxOverheadPercent: legacyMaxOverheadPercent) ?? FunderOverheadRule())
    }

    /// The plan for an application with this grant provider and fund
    /// manager (both found by id before this is called).
    static func resolved(funder: OrganizationRecord?, manager: OrganizationRecord?) -> GrantOverheadPlan {
        GrantOverheadPlan(
            rule: funder?.resolvedOverheadRule(forManagerOrganizationID: manager?.id) ?? FunderOverheadRule(),
            managerOverheadPeriods: manager?.salaryCalculator?.overheadPeriods ?? [],
            managerOverheadPercent: manager?.managerOverheadPercent
        )
    }
}

extension GrantDataStore {
    /// The OH plan of an application: the grant provider and the fund
    /// manager are found by id first (the written name only for older rows).
    func overheadPlan(for application: GrantApplication) -> GrantOverheadPlan {
        let managerOrganization = linkedFundManager(of: application).flatMap { organization(id: $0.id) }
        return GrantOverheadPlan.resolved(funder: linkedFunder(of: application), manager: managerOrganization)
    }

    /// The organizations with the role fund manager, for the exception rows
    /// on a grant provider.
    var fundManagerOrganizations: [OrganizationRecord] {
        organizations
            .filter { $0.roles.contains(.fundManager) }
            .sorted { $0.nameSv.localizedStandardCompare($1.nameSv) == .orderedAscending }
    }
}

/// The text next to the salary budget in the application editor, for
/// example "OH: 15 % (förvaltarens 20 %, anslagsgivarens tak 15 %)".
func grantOverheadSummaryText(
    managerPercent: Double,
    effectivePercent: Double,
    rule: FunderOverheadRule,
    language: AppLanguage
) -> String {
    let effective = grantFormattedPercent(effectivePercent)
    let manager = grantFormattedPercent(managerPercent)
    let funderPart: String
    switch rule.kind {
    case .managerFull:
        funderPart = language.text("the grant provider accepts the full OH", "anslagsgivaren godtar full OH")
    case .cap:
        if let cap = rule.effectiveCapPercent {
            funderPart = language.text("grant provider's cap \(grantFormattedPercent(cap))", "anslagsgivarens tak \(grantFormattedPercent(cap))")
        } else {
            funderPart = language.text("no cap entered at the grant provider", "inget tak ifyllt hos anslagsgivaren")
        }
    case .noOverhead:
        funderPart = language.text("the grant provider gives no OH", "anslagsgivaren ger ingen OH")
    }
    return language.text(
        "OH: \(effective) (fund manager's \(manager), \(funderPart))",
        "OH: \(effective) (förvaltarens \(manager), \(funderPart))"
    )
}

/// "20 %", "12,5 %" (Swedish decimal comma, at most two decimals).
func grantFormattedPercent(_ percent: Double) -> String {
    let rounded = (percent * 100).rounded() / 100
    var text: String
    if rounded == rounded.rounded() {
        text = String(Int(rounded))
    } else {
        text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        text = text.replacingOccurrences(of: ".", with: ",")
    }
    return "\(text) %"
}
