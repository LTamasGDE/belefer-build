import SwiftUI
import WidgetKit

// Belefér kezdőképernyő-widget: a hónap egyenlege, bevétele, kiadása és a
// következő esedékes tétel. Az adatokat az alkalmazás írja a közös App
// Group tárolóba (home_widget, `belefer_*` kulcsok).

private let widgetKind = "BeleferWidget"
private let fallbackAppGroup = "group.com.ventyh1.belefer"

private let ink = Color(red: 0x10 / 255, green: 0x1A / 255, blue: 0x3C / 255)
private let cream = Color(red: 0xF6 / 255, green: 0xF0 / 255, blue: 0xE5 / 255)
private let creamSoft = Color(red: 0xB5 / 255, green: 0xBB / 255, blue: 0xD6 / 255)
private let teal = Color(red: 0x19 / 255, green: 0xD3 / 255, blue: 0xC5 / 255)
private let mint = Color(red: 0x4F / 255, green: 0xE0 / 255, blue: 0xA6 / 255)
private let coral = Color(red: 0xFF / 255, green: 0x81 / 255, blue: 0x78 / 255)

/// A tényleges App Group azonosító a telepítési profilból. Az ingyenes
/// telepítés (SideStore) átnevezheti a csoportot; így mindig azt használjuk,
/// amit a rendszer valóban engedélyezett.
private func resolvedAppGroup() -> String {
  guard
    let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
    let data = try? Data(contentsOf: url),
    let text = String(data: data, encoding: .isoLatin1),
    let key = text.range(of: "<key>com.apple.security.application-groups</key>")
  else { return fallbackAppGroup }
  let rest = text[key.upperBound...]
  guard
    let start = rest.range(of: "<string>"),
    let end = rest.range(of: "</string>", range: start.upperBound..<rest.endIndex)
  else { return fallbackAppGroup }
  let group = rest[start.upperBound..<end.lowerBound]
    .trimmingCharacters(in: .whitespacesAndNewlines)
  return group.isEmpty ? fallbackAppGroup : group
}

struct BeleferEntry: TimelineEntry {
  let date: Date
  let month: String
  let balance: String
  let income: String
  let expense: String
  let next: String
  let negative: Bool
  let hasData: Bool

  static let sample = BeleferEntry(
    date: Date(),
    month: "november",
    balance: "124 500 Ft",
    income: "420 000 Ft",
    expense: "295 500 Ft",
    next: "Lakbér: 180 000 Ft, dec. 1.",
    negative: false,
    hasData: true
  )

  static func load() -> BeleferEntry {
    let defaults = UserDefaults(suiteName: resolvedAppGroup())
    guard let month = defaults?.string(forKey: "belefer_month") else {
      return BeleferEntry(
        date: Date(), month: "", balance: "", income: "", expense: "", next: "",
        negative: false, hasData: false)
    }
    return BeleferEntry(
      date: Date(),
      month: month,
      balance: defaults?.string(forKey: "belefer_balance") ?? "",
      income: defaults?.string(forKey: "belefer_income") ?? "",
      expense: defaults?.string(forKey: "belefer_expense") ?? "",
      next: defaults?.string(forKey: "belefer_next") ?? "",
      negative: defaults?.string(forKey: "belefer_negative") == "1",
      hasData: true
    )
  }
}

struct BeleferProvider: TimelineProvider {
  func placeholder(in context: Context) -> BeleferEntry { .sample }

  func getSnapshot(in context: Context, completion: @escaping (BeleferEntry) -> Void) {
    let entry = BeleferEntry.load()
    completion(context.isPreview && !entry.hasData ? .sample : entry)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<BeleferEntry>) -> Void) {
    // Az alkalmazás minden változáskor frissíti a widgetet; éjfél után
    // (új hónap) is újraolvassuk.
    let calendar = Calendar.current
    let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
    completion(Timeline(entries: [BeleferEntry.load()], policy: .after(tomorrow)))
  }
}

private extension View {
  @ViewBuilder
  func beleferBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(ink, for: .widget)
    } else {
      padding().background(ink)
    }
  }
}

private func link(_ path: String) -> URL {
  URL(string: "belefer://\(path)?homeWidget=1")!
}

struct BeleferWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: BeleferEntry

  var body: some View {
    content
      .beleferBackground()
      .widgetURL(link("gyors"))
  }

  @ViewBuilder
  private var content: some View {
    if !entry.hasData {
      VStack(alignment: .leading, spacing: 6) {
        Text("Belefér").font(.headline).foregroundColor(cream)
        Text("Nyisd meg az alkalmazást, és itt látod, mennyi maradt.")
          .font(.caption).foregroundColor(creamSoft)
        Spacer(minLength: 0)
        quickButton
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else if family == .systemSmall {
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.month.capitalized).font(.caption2).foregroundColor(creamSoft).lineLimit(1)
        Spacer(minLength: 0)
        Text("Maradt").font(.caption).foregroundColor(creamSoft)
        Text(entry.balance)
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .foregroundColor(entry.negative ? coral : cream)
          .minimumScaleFactor(0.5)
          .lineLimit(1)
        Spacer(minLength: 0)
        quickButton
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text("Belefér · \(entry.month)").font(.caption).foregroundColor(creamSoft).lineLimit(1)
          Spacer()
        }
        Text("Maradt").font(.caption).foregroundColor(creamSoft)
        Text(entry.balance)
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundColor(entry.negative ? coral : cream)
          .minimumScaleFactor(0.5)
          .lineLimit(1)
        HStack(spacing: 12) {
          Text("↓ \(entry.income)").font(.caption).foregroundColor(mint).lineLimit(1)
          Text("↑ \(entry.expense)").font(.caption).foregroundColor(coral).lineLimit(1)
        }
        if !entry.next.isEmpty {
          Text("Következő: \(entry.next)").font(.caption2).foregroundColor(creamSoft).lineLimit(1)
        }
        Spacer(minLength: 0)
        HStack(spacing: 8) {
          quickButton
          Link(destination: link("blokk")) {
            Image(systemName: "camera.fill")
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(teal)
              .frame(width: 36, height: 30)
              .background(Color.white.opacity(0.12))
              .clipShape(Capsule())
          }
          .accessibilityLabel("Blokk fotózása")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var quickButton: some View {
    Link(destination: link("gyors")) {
      Text("+ Gyorsrögzítés")
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(teal)
        .clipShape(Capsule())
    }
  }
}

@main
struct BeleferWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: widgetKind, provider: BeleferProvider()) { entry in
      BeleferWidgetView(entry: entry)
    }
    .configurationDisplayName("Belefér")
    .description("Mennyi maradt a hónapban, és mi a következő esedékes tétel.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
