import EventKit

struct EventSegment: Identifiable {
    let id: String
    let event: EKEvent
    let month: Int
    let startDay: Int
    let endDay: Int
    let lane: Int
}

enum EventLayoutEngine {
    private struct DaySpan {
        let month: Int
        let startDay: Int
        let endDay: Int
    }

    private static func daySpans(for event: EKEvent, year: Int, calendar cal: Calendar) -> [DaySpan] {
        guard let startDate = event.startDate, let rawEnd = event.endDate else { return [] }
        let endDate = rawEnd >= startDate ? rawEnd : startDate

        let sc = cal.dateComponents([.year, .month, .day], from: startDate)
        let ec = cal.dateComponents([.year, .month, .day], from: endDate)

        guard let scYear = sc.year, let scMonth = sc.month, let scDay = sc.day,
              let ecYear = ec.year, let ecMonth = ec.month, let ecDay = ec.day,
              scYear <= year, ecYear >= year else { return [] }

        let firstMonth = scYear < year ? 1 : scMonth
        let lastMonth = ecYear > year ? 12 : ecMonth
        guard firstMonth >= 1, lastMonth <= 12, firstMonth <= lastMonth else { return [] }

        var spans: [DaySpan] = []
        for month in firstMonth...lastMonth {
            guard let monthDate = cal.date(from: DateComponents(year: year, month: month)),
                  let range = cal.range(of: .day, in: .month, for: monthDate) else { continue }
            let daysInMonth = range.count
            let sDay = (scYear == year && scMonth == month) ? scDay : 1
            let eDay = (ecYear == year && ecMonth == month) ? min(ecDay, daysInMonth) : daysInMonth
            guard sDay <= eDay else { continue }
            spans.append(DaySpan(month: month, startDay: sDay, endDay: eDay))
        }
        return spans
    }

    static func layout(events: [EKEvent], year: Int, maxLanes: Int) -> [EventSegment] {
        let cal = Calendar.current
        var rawByMonth: [Int: [(event: EKEvent, startDay: Int, endDay: Int)]] = [:]

        for event in events {
            for span in daySpans(for: event, year: year, calendar: cal) {
                rawByMonth[span.month, default: []].append((event, span.startDay, span.endDay))
            }
        }

        var result: [EventSegment] = []

        for month in 1...12 {
            guard let segs = rawByMonth[month] else { continue }

            let sorted = segs.sorted {
                if $0.startDay != $1.startDay { return $0.startDay < $1.startDay }
                return ($0.endDay - $0.startDay) > ($1.endDay - $1.startDay)
            }

            // dayLanes[day] = set of occupied lanes
            var dayLanes: [Int: Set<Int>] = [:]

            for seg in sorted {
                var lane = 0
                while lane < maxLanes {
                    let occupied = (seg.startDay...seg.endDay).contains { day in
                        dayLanes[day, default: []].contains(lane)
                    }
                    if !occupied { break }
                    lane += 1
                }
                guard lane < maxLanes else { continue } // overflow, skip

                for day in seg.startDay...seg.endDay {
                    dayLanes[day, default: []].insert(lane)
                }

                // eventIdentifier 미존재 시 ObjectIdentifier로 고유 ID 보장 (저장되지 않은 EKEvent 대비)
                let eventKey = seg.event.eventIdentifier ?? String(UInt(bitPattern: ObjectIdentifier(seg.event).hashValue))
                result.append(EventSegment(
                    id: "\(eventKey)_\(month)",
                    event: seg.event,
                    month: month,
                    startDay: seg.startDay,
                    endDay: seg.endDay,
                    lane: lane
                ))
            }
        }

        return result
    }

    /// 월별 셀당 overflow 카운트 (maxLanes 초과 이벤트 수)
    static func overflowCounts(events: [EKEvent], year: Int, maxLanes: Int) -> [Int: [Int: Int]] {
        // [month: [day: overflowCount]]
        let cal = Calendar.current
        var dayCounts: [Int: [Int: Int]] = [:]

        for event in events {
            for span in daySpans(for: event, year: year, calendar: cal) {
                for day in span.startDay...span.endDay {
                    dayCounts[span.month, default: [:]][day, default: 0] += 1
                }
            }
        }

        var result: [Int: [Int: Int]] = [:]
        for (month, days) in dayCounts {
            for (day, count) in days where count > maxLanes {
                result[month, default: [:]][day] = count - maxLanes
            }
        }
        return result
    }
}
