import SwiftUI

struct SMSDashboardView: View {
    @StateObject private var vm = SMSDashboardViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Select Country") {
                    Picker("Country", selection: $vm.selectedCountry) {
                        Text("Choose...").tag(Optional<Country>.none)
                        ForEach(vm.countries) { country in
                            Text("\(country.name) (\(country.isoCode))")
                                .tag(Optional(country))
                        }
                    }
                }

                Section("Reserved Number") {
                    Text(vm.reservedNumber ?? "No number reserved yet")
                        .font(.headline)
                        .foregroundStyle(vm.reservedNumber == nil ? .secondary : .primary)

                    Button(vm.isLoading ? "Reserving..." : "Reserve Number") {
                        Task { await vm.reserveNumber() }
                    }
                    .disabled(vm.selectedCountry == nil || vm.isLoading)
                }

                Section("Latest Incoming SMS") {
                    if let message = vm.latestMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("From: \(message.from)")
                            Text(message.body)
                                .font(.title3)
                                .bold()
                            Text(message.receivedAt.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Listening for incoming verification code...")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorText = vm.errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("SMS Dashboard")
        }
        .task { vm.startRealtimeListener() }
    }
}

#Preview {
    SMSDashboardView()
}
