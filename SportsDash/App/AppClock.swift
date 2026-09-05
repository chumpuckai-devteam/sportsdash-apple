import Foundation
import Observation

/// Shared wall-clock truncated to the minute so Equatable Guide/Scores rows
/// do not re-evaluate on sub-second `Date()` noise. One timer for the process.
@Observable
@MainActor
final class AppClock {
    private(set) var minute: Date
    private var timer: Timer?

    init(now: Date = Date()) {
        self.minute = Self.truncated(now)
        arm(from: now)
    }

    deinit {
        timer?.invalidate()
    }

    static func truncated(_ date: Date) -> Date {
        let cal = Calendar.current
        let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return cal.date(from: parts) ?? date
    }

    private func arm(from now: Date) {
        timer?.invalidate()
        let delay = 60 - now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        timer = Timer.scheduledTimer(withTimeInterval: max(0.05, delay), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.tickAndRepeat()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func tickAndRepeat() {
        minute = Self.truncated(Date())
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.minute = AppClock.truncated(Date())
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}
