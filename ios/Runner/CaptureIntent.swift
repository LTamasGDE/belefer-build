import AppIntents
import Foundation

/// Az automatikus rögzítésre váró Apple Pay-fizetések sora (az alkalmazás
/// saját tárolójában), amíg a Belefér meg nem nyílik és fel nem dolgozza.
enum CaptureStore {
  private static let queueKey = "belefer_capture_queue"

  static func append(_ event: [String: Any]) {
    let defaults = UserDefaults.standard
    var queue = defaults.array(forKey: queueKey) as? [[String: Any]] ?? []
    queue.append(event)
    if queue.count > 200 { queue.removeFirst(queue.count - 200) }
    defaults.set(queue, forKey: queueKey)
  }

  static func drain() -> [[String: Any]] {
    let defaults = UserDefaults.standard
    let queue = defaults.array(forKey: queueKey) as? [[String: Any]] ?? []
    defaults.set([[String: Any]](), forKey: queueKey)
    return queue
  }
}

/// Parancsok-művelet: egy Apple Pay-fizetés átadása a Belefér-nek. A
/// Parancsok „Wallet” (Tranzakció) automatizmusa hívja minden fizetés után a
/// kiválasztott kártyával; az alkalmazás nem nyílik meg.
@available(iOS 16.0, *)
struct LogApplePayPaymentIntent: AppIntent {
  static var title: LocalizedStringResource = "Fizetés rögzítése a Belefér-ben"
  static var description = IntentDescription(
    "Egy Apple Pay-fizetés (összeg, kereskedő, kártya) automatikus rögzítése. A Belefér a következő megnyitáskor könyveli."
  )
  static var openAppWhenRun: Bool = false

  @Parameter(title: "Összeg")
  var amount: String

  @Parameter(title: "Kereskedő")
  var merchant: String?

  @Parameter(title: "Kártya")
  var card: String?

  static var parameterSummary: some ParameterSummary {
    Summary("Fizetés rögzítése: \(\.$amount) – \(\.$merchant) (\(\.$card))")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let now = Date()
    var event: [String: Any] = [
      "id": UUID().uuidString,
      "source": "applepay",
      "time": Int(now.timeIntervalSince1970 * 1000),
      "amount": amount,
    ]
    if let merchant, !merchant.isEmpty { event["merchant"] = merchant }
    if let card, !card.isEmpty { event["card"] = card }
    CaptureStore.append(event)
    let what = (merchant?.isEmpty == false ? merchant! : "Fizetés")
    return .result(dialog: "Belefér: \(what), \(amount) – rögzítem.")
  }
}
