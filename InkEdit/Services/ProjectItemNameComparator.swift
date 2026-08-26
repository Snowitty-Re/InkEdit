import Foundation

enum ProjectItemNameComparator {
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        let lhsKey = normalizedOrdinalKey(for: lhs)
        let rhsKey = normalizedOrdinalKey(for: rhs)

        return switch lhsKey.localizedStandardCompare(rhsKey) {
        case .orderedAscending:
            true
        case .orderedDescending:
            false
        case .orderedSame:
            lhs < rhs
        }
    }

    private static let ordinalSuffixes: Set<Character> = ["章", "节", "卷", "部", "篇", "幕", "回", "集", "册", "话"]
    private static let digitValues: [Character: Int] = [
        "零": 0, "〇": 0, "○": 0,
        "一": 1, "壹": 1,
        "二": 2, "两": 2, "兩": 2, "贰": 2, "貳": 2,
        "三": 3, "叁": 3, "參": 3,
        "四": 4, "肆": 4,
        "五": 5, "伍": 5,
        "六": 6, "陆": 6, "陸": 6,
        "七": 7, "柒": 7,
        "八": 8, "捌": 8,
        "九": 9, "玖": 9,
    ]
    private static let smallUnitValues: [Character: Int] = [
        "十": 10, "拾": 10,
        "百": 100, "佰": 100,
        "千": 1_000, "仟": 1_000,
    ]
    private static let largeUnitValues: [Character: Int] = [
        "万": 10_000, "萬": 10_000,
        "亿": 100_000_000, "億": 100_000_000,
    ]

    private static func normalizedOrdinalKey(for name: String) -> String {
        var key = ""
        var index = name.startIndex

        while index < name.endIndex {
            guard name[index] == "第" else {
                key.append(name[index])
                index = name.index(after: index)
                continue
            }

            let numeralStart = name.index(after: index)
            var numeralEnd = numeralStart
            while numeralEnd < name.endIndex, isChineseNumeral(name[numeralEnd]) {
                numeralEnd = name.index(after: numeralEnd)
            }

            guard
                numeralEnd > numeralStart,
                numeralEnd < name.endIndex,
                ordinalSuffixes.contains(name[numeralEnd]),
                let value = chineseNumberValue(String(name[numeralStart..<numeralEnd]))
            else {
                key.append(name[index])
                index = numeralStart
                continue
            }

            key.append("第")
            key.append(String(value))
            key.append(name[numeralEnd])
            index = name.index(after: numeralEnd)
        }

        return key
    }

    private static func isChineseNumeral(_ character: Character) -> Bool {
        digitValues[character] != nil || smallUnitValues[character] != nil || largeUnitValues[character] != nil
    }

    private static func chineseNumberValue(_ numeral: String) -> Int? {
        let characters = Array(numeral)
        guard !characters.isEmpty else { return nil }

        if characters.allSatisfy({ digitValues[$0] != nil }) {
            var value = 0
            for character in characters {
                guard
                    let product = safeMultiply(value, 10),
                    let sum = safeAdd(product, digitValues[character] ?? 0)
                else {
                    return nil
                }
                value = sum
            }
            return value
        }

        var total = 0
        var section = 0
        var digit: Int?

        for character in characters {
            if let value = digitValues[character] {
                digit = value
            } else if let unit = smallUnitValues[character] {
                guard let product = safeMultiply(digit ?? 1, unit), let sum = safeAdd(section, product) else {
                    return nil
                }
                section = sum
                digit = nil
            } else if let unit = largeUnitValues[character] {
                if let digit {
                    guard let sum = safeAdd(section, digit) else { return nil }
                    section = sum
                }
                guard let product = safeMultiply(max(section, 1), unit), let sum = safeAdd(total, product) else {
                    return nil
                }
                total = sum
                section = 0
                digit = nil
            } else {
                return nil
            }
        }

        guard let sectionTotal = safeAdd(section, digit ?? 0) else { return nil }
        return safeAdd(total, sectionTotal)
    }

    private static func safeAdd(_ lhs: Int, _ rhs: Int) -> Int? {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? nil : result.partialValue
    }

    private static func safeMultiply(_ lhs: Int, _ rhs: Int) -> Int? {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? nil : result.partialValue
    }
}
