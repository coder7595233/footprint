import Foundation

extension TeachingCourse {
    /// F7: the code that applied on a given ISO day; the current one otherwise.
    func courseCode(on day: String?) -> String {
        guard let day = day?.trimmingCharacters(in: .whitespacesAndNewlines), !day.isEmpty else {
            return courseCode
        }
        if let match = courseCodes.first(where: { $0.covers(day: day) }) {
            return match.code
        }
        return courseCode
    }

    /// F4: whether the catalogue row was valid on a given ISO day.
    func isValid(on day: String) -> Bool {
        let day = day.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !day.isEmpty else { return validTo.isEmpty }
        if !validFrom.isEmpty, day < validFrom { return false }
        if !validTo.isEmpty, day > validTo { return false }
        return true
    }
}
