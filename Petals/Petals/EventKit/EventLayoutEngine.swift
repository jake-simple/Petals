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
    static func layout(events: [EKEvent], year: Int, maxLanes: Int) -> [EventSegment] {
        let cal = Calendar.current
        var rawByMonth: [Int: [(event: EKEvent, startDay: Int, endDay: Int)]] = [:]

        for event in events {
            let startDate = event.startDate!
            let rawEnd = event.endDate!
            let endDate: Date
            if event.isAllDay {
                let adjusted = cal.date(byAdding: .day, value: -1, to: rawEnd) ?? rawEnd
                endDate = adjusted >= startDate ? adjusted : startDate
            } else {
                endDate = rawEnd >= startDate ? rawEnd : startDate
            }

            let sc = cal.dateComponents([.year, .month, .day], from: startDate)
            let ec = cal.dateComponents([.year, .month, .day], from: endDate)

            // Skip events entirely outside this year
            guard sc.year! <= year, ec.year! >= year else { continue }

            let firstMonth = sc.year! < year ? 1 : sc.month!
            let lastMonth = ec.year! > year ? 12 : ec.month!
            guard firstMonth >= 1, lastMonth <= 12, firstMonth <= lastMonth else { continue }

            for month in firstMonth...lastMonth {
                let daysInMonth = cal.range(
                    of: .day, in: .month,
                    for: cal.date(from: DateComponents(year: year, month: month))!
                )!.count

                let sDay = (sc.year == year && sc.month == month) ? sc.day! : 1
                let eDay = (ec.year == year && ec.month == month) ? min(ec.day!, daysInMonth) : daysInMonth
                guard sDay <= eDay else { continue }

                rawByMonth[month, default: []].append((event, sDay, eDay))
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

                result.append(EventSegment(
                    id: "\(seg.event.eventIdentifier ?? UUID().uuidString)_\(month)",
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
        var dayCounts: [Int: [Int: Int]] = [:]  // [month: [day: totalCount]]

        for event in events {
            let startDate = event.startDate!
            let rawEnd = event.endDate!
            let endDate: Date
            if event.isAllDay {
                let adjusted = cal.date(byAdding: .day, value: -1, to: rawEnd) ?? rawEnd
                endDate = adjusted >= startDate ? adjusted : startDate
            } else {
                endDate = rawEnd >= startDate ? rawEnd : startDate
            }

            let sc = cal.dateComponents([.year, .month, .day], from: startDate)
            let ec = cal.dateComponents([.year, .month, .day], from: endDate)

            guard sc.year! <= year, ec.year! >= year else { continue }

            let firstMonth = sc.year! < year ? 1 : sc.month!
            let lastMonth = ec.year! > year ? 12 : ec.month!
            guard firstMonth >= 1, lastMonth <= 12, firstMonth <= lastMonth else { continue }

            for month in firstMonth...lastMonth {
                let daysInMonth = cal.range(
                    of: .day, in: .month,
                    for: cal.date(from: DateComponents(year: year, month: month))!
                )!.count
                let sDay = (sc.year == year && sc.month == month) ? sc.day! : 1
                let eDay = (ec.year == year && ec.month == month) ? min(ec.day!, daysInMonth) : daysInMonth
                guard sDay <= eDay else { continue }

                for day in sDay...eDay {
                    dayCounts[month, default: [:]][day, default: 0] += 1
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
