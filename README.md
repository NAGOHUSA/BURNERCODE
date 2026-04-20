# BURNERCODE

## System Architecture (Text Diagram)

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ iOS App (SwiftUI)                                                      │
│ - Country list + number reservation UI                                 │
│ - Shows reserved number + incoming OTP code                            │
│ - Uses StoreKit credits (consumable IAP)                               │
│ - Realtime listener (Supabase Realtime / Firebase listener)            │
└───────────────┬─────────────────────────────────────────────────────────┘
                │ HTTPS (JWT-authenticated)
                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Serverless API Layer (Supabase Edge Functions or Firebase Functions)   │
│ - POST /reserve-number (debit credits, provision number via provider)  │
│ - POST /release-number                                                  │
│ - POST /provider-webhook (receive inbound SMS from Twilio/Telnyx)      │
│ - Verifies provider signature + normalizes payload                      │
└───────────────┬─────────────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Data Layer (Supabase Postgres / Firebase Firestore)                    │
│ Tables/Collections: users, credit_ledger, reservations, sms_messages   │
│ Realtime stream pushes new OTP messages to the device                  │
└───────────────┬─────────────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ SMS Provider (Twilio / Telnyx)                                         │
│ - Buy/assign virtual numbers                                            │
│ - Route incoming SMS to serverless webhook                              │
└─────────────────────────────────────────────────────────────────────────┘
```

## Backend Integration Blueprint

- **Recommended provider:** Start with **Twilio** for mature APIs, webhook signing, and global number inventory. Telnyx is a strong cost alternative.
- **Number sourcing flow:**
  1. iOS calls `reserve-number` with selected country.
  2. Function checks user credit balance.
  3. Function provisions or leases a number from provider API.
  4. Function stores reservation and returns number + reservation id.
- **Incoming SMS flow:**
  1. Provider sends webhook to `provider-webhook`.
  2. Function verifies provider signature/token.
  3. Normalize payload (`from`, `to`, `body`, `received_at`).
  4. Persist message and emit realtime update to reservation owner.

### Example webhook boilerplate (Supabase Edge Function style)

```ts
// pseudo/boilerplate
import { createClient } from "@supabase/supabase-js";

Deno.serve(async (req) => {
  const signature = req.headers.get("X-Twilio-Signature") ?? "";
  const form = await req.formData();

  // TODO: verify signature with your Twilio auth token
  if (!signature) return new Response("invalid signature", { status: 401 });

  const to = String(form.get("To") ?? "");
  const from = String(form.get("From") ?? "");
  const body = String(form.get("Body") ?? "");

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  await supabase.from("sms_messages").insert({
    to_number: to,
    from_number: from,
    body,
    received_at: new Date().toISOString(),
  });

  return new Response("ok", { status: 200 });
});
```

## Pay-per-SMS Business Logic (No Subscription)

- Use **StoreKit consumable IAPs** for credits (e.g., 20/50/100 credits packs).
- On successful purchase, server validates App Store receipt and increments `credit_ledger`.
- Debit model example:
  - `reserve-number`: -1 credit
  - `first SMS received`: -1 credit
  - optional timeout/auto-release policy to avoid number hoarding
- Keep pricing transparent in-app (per action) to align with App Store expectations.

## App Store Compliance Notes (Utility Category)

Pay attention to these review areas:

- **Guideline 2.1 – App Completeness:** production-ready flow, no placeholder purchase/message UX.
- **Guideline 3.1.1 – In-App Purchase:** digital credits consumed in-app must use IAP.
- **Guideline 5.1.1 – Data Collection & Storage:** clear privacy policy, data minimization, retention rules for SMS.
- **Guideline 5.1.2 – User Consent:** inform users about message handling and third-party telecom processors.
- **Guideline 1.1 / 1.2 – Safety/Abuse:** enforce anti-abuse controls (rate limits, banned destinations, fraud checks).

## SwiftUI: Primary SMS Dashboard View

```swift
import SwiftUI

struct Country: Identifiable, Hashable {
    let id = UUID()
    let isoCode: String
    let name: String
}

struct SMSMessage: Identifiable, Hashable {
    let id = UUID()
    let from: String
    let body: String
    let receivedAt: Date
}

@MainActor
final class SMSDashboardViewModel: ObservableObject {
    @Published var countries: [Country] = [
        .init(isoCode: "US", name: "United States"),
        .init(isoCode: "GB", name: "United Kingdom"),
        .init(isoCode: "CA", name: "Canada"),
        .init(isoCode: "DE", name: "Germany")
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
            reservedNumber = "+1 555 010 42\(selectedCountry.isoCode.suffix(1))"
            errorText = nil
        } catch {
            errorText = "Failed to reserve number. Try again."
        }
    }

    func startRealtimeListener() {
        // Replace with Supabase/Firebase realtime subscription.
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            latestMessage = SMSMessage(
                from: "+1 202 555 0147",
                body: "Your verification code is 483921",
                receivedAt: Date()
            )
        }
    }
}

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
```

## UI Mock Screenshot

![SMS Dashboard Mock](https://github.com/user-attachments/assets/4ceda08c-3672-454b-9235-8214553cc5df)
