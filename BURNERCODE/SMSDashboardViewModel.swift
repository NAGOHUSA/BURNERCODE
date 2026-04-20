import SwiftUI

@MainActor
final class SMSDashboardViewModel: ObservableObject {
    private let mockReservedNumberPrefix = "555-010-42" // Placeholder mock format.
    private var listenerTask: Task<Void, Never>?

    @Published var countries: [Country] = [
        .init(isoCode: "US", name: "United States", dialingCode: "+1"),
        .init(isoCode: "GB", name: "United Kingdom", dialingCode: "+44"),
        .init(isoCode: "CA", name: "Canada", dialingCode: "+1"),
        .init(isoCode: "DE", name: "Germany", dialingCode: "+49")
    ]
    @Published var selectedCountry: Country?
    @Published var reservedNumber: String?
    @Published var latestMessage: SMSMessage?
    @Published var isLoading = false
    @Published var errorText: String?

    func reserveNumber() async {
        guard let selectedCountry else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // Replace with API call to your serverless function.
            try await Task.sleep(nanoseconds: 300_000_000)
            reservedNumber = "\(selectedCountry.dialingCode) \(mockReservedNumberPrefix)\(Int.random(in: 10...99))"
            errorText = nil
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Unable to reserve number. Check credit balance, connectivity, and provider availability."
        }
    }

    func startRealtimeListener() {
        // Replace with Supabase/Firebase realtime subscription.
        listenerTask?.cancel()
        listenerTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                latestMessage = SMSMessage(
                    from: "+1 202 555 0147",
                    body: "Your verification code is 483921",
                    receivedAt: Date()
                )
            } catch {
                errorText = "Realtime listener interrupted. Reconnecting may be required."
            }
        }
    }

    deinit {
        listenerTask?.cancel()
    }
}
