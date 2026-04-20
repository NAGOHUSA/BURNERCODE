import Foundation

struct Country: Identifiable, Hashable {
    let id = UUID()
    let isoCode: String
    let name: String
    let dialingCode: String
}

struct SMSMessage: Identifiable, Hashable {
    let id = UUID()
    let from: String
    let body: String
    let receivedAt: Date
}
