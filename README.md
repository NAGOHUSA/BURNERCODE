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

/**
 * Validates Twilio webhook authenticity by recomputing the expected HMAC-SHA1 signature
 * from the public webhook URL + sorted form fields and comparing it to X-Twilio-Signature.
 */
async function verifyTwilioSignature(req: Request, form: FormData, authToken: string, publicWebhookUrl: string) {
  const signature = req.headers.get("X-Twilio-Signature") ?? "";
  if (!signature) return false;

  // Twilio signature base string: full webhook URL + concatenated sorted form fields.
  const pairs = [...form.entries()]
    .map(([k, v]) => [String(k), String(v)] as const)
    .sort(([a], [b]) => a.localeCompare(b));
  const payload = publicWebhookUrl + pairs.map(([k, v]) => `${k}${v}`).join("");

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(authToken),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"]
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  const expected = btoa(String.fromCharCode(...new Uint8Array(mac)));
  return signature === expected;
}

Deno.serve(async (req) => {
  const form = await req.formData();
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const twilioAuthToken = Deno.env.get("TWILIO_AUTH_TOKEN");
  const publicWebhookUrl = Deno.env.get("PUBLIC_WEBHOOK_URL");

  if (!supabaseUrl || !serviceRoleKey || !twilioAuthToken || !publicWebhookUrl) {
    return new Response("Missing required environment configuration", { status: 500 });
  }

  const isValid = await verifyTwilioSignature(req, form, twilioAuthToken, publicWebhookUrl);
  if (!isValid) return new Response("invalid signature", { status: 401 });

  const to = String(form.get("To") ?? "");
  const from = String(form.get("From") ?? "");
  const body = String(form.get("Body") ?? "");

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const { error } = await supabase.from("sms_messages").insert({
      to_number: to,
      from_number: from,
      body,
      received_at: new Date().toISOString(),
    });
  if (error) return new Response("failed to persist inbound SMS", { status: 500 });

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
    let dialingCode: String
}

struct SMSMessage: Identifiable, Hashable {
    let id = UUID()
    let from: String
    let body: String
    let receivedAt: Date
}

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
