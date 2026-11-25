import Foundation

enum BulletPointFormatter {
    private static let markers = ["- ", "* ", "•", "・"]

    /// Normalizes list markers without rewriting, splitting, or summarizing the model's text.
    static func normalized(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "" }

        // Preserve a heading only when the following line already has a list marker.
        let hasHeading = lines.count > 1 && marker(in: lines[0]) == nil && marker(in: lines[1]) != nil
        var output = lines.enumerated().map { index, line in
            if index == 0, hasHeading { return line }
            let content = marker(in: line).map { String(line.dropFirst($0.count)) } ?? line
            return "- " + content.trimmingCharacters(in: .whitespaces)
        }
        if hasHeading { output.insert("", at: 1) }
        return output.joined(separator: "\n")
    }

    private static func marker(in line: String) -> String? {
        markers.first { line.hasPrefix($0) }
    }
}

enum DateGrouping {
    static func title(for date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return Self.sectionFormatter.string(from: date)
    }

    private static let sectionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

