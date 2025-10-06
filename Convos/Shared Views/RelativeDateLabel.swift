import ConvosCore
import SwiftUI

struct RelativeDateLabel: View {
    let date: Date
    @State private var timer: Timer?
    @State private var dateString: String = ""

    var body: some View {
        Text(dateString)
            .textCase(.lowercase)
            .onAppear {
                dateString = date.relativeShort()
                startTimer()
            }
            .onChange(of: date) {
                dateString = date.relativeShort()
            }
            .onDisappear {
                stopTimer()
            }
    }

    private func startTimer() {
        stopTimer()
        let interval = nextUpdateInterval()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            dateString = date.relativeShort()
            startTimer()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func nextUpdateInterval() -> TimeInterval {
        let secondsAgo = abs(Date().timeIntervalSince(date))
        if secondsAgo < 60 {
            return TimeInterval(30.0)
        } else if secondsAgo < 1800 {
            return TimeInterval(120.0)
        } else if secondsAgo < 3600 {
            let secondsToNextMinute = 60 - (Int(secondsAgo) % 60)
            return TimeInterval(secondsToNextMinute)
        } else {
            let secondsToNextHour = 3600 - (Int(secondsAgo) % 3600)
            return TimeInterval(secondsToNextHour)
        }
    }
}
