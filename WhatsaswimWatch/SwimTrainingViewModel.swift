import Foundation
import Combine

final class SwimTrainingViewModel: ObservableObject {
    @Published var elapsedTime: TimeInterval = 0
    @Published var isPaused: Bool = false
    
    private var timer: Timer?
    
    func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused else { return }
            self.elapsedTime += 1
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        stopTimer()
    }
}
