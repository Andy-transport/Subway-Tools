import SwiftUI
import WidgetKit
import ActivityKit

// Live Activity widget (build 65): renders the active trip on the Lock
// Screen and in the Dynamic Island. All labels and station names arrive
// pre-localized from the app (in TripAttributes / ContentState), so this
// view does no localization itself. The countdown uses Text(timer),
// which the system keeps ticking even when the app is suspended.

@main
struct LiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripAttributes.self) { context in
            TripLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TripIslandLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TripIslandTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TripIslandBottom(context: context)
                }
            } compactLeading: {
                Label("\(context.state.remainingStops)", systemImage: "tram.fill")
            } compactTrailing: {
                Text(context.state.arrivalDate, style: .timer)
                    .font(.caption2)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "tram.fill")
            }
        }
    }
}

// MARK: - Helpers

func colorFromHex(_ hex: String) -> Color {
    var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = Int(h, radix: 16) else { return Color.blue }
    let r = Double((v >> 16) & 0xFF) / 255
    let g = Double((v >> 8) & 0xFF) / 255
    let b = Double(v & 0xFF) / 255
    return Color(red: r, green: g, blue: b)
}

func stopsText(_ format: String, _ n: Int) -> String {
    return format.replacingOccurrences(of: "{n}", with: "\(n)")
}

// MARK: - Lock Screen (banner)

struct TripLockScreenView: View {
    let context: ActivityViewContext<TripAttributes>
    var body: some View {
        let theme = colorFromHex(context.attributes.themeHex)
        let state = context.state
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if !context.attributes.lineName.isEmpty {
                    Text(context.attributes.lineName)
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(theme)
                        .clipShape(Capsule())
                }
                Text(context.attributes.fromName + " → " + context.attributes.toName)
                    .font(.headline)
                    .lineLimit(1)
            }
            if state.status == "arrived" {
                Text(context.attributes.arrivedLabel)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(theme)
            } else {
                HStack {
                    Text(context.attributes.nextLabel + " " + state.nextStation)
                        .font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    Text(stopsText(context.attributes.stopsFormat, state.remainingStops))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(state.arrivalDate, style: .timer)
                        .font(.subheadline).fontWeight(.bold)
                        .monospacedDigit()
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Dynamic Island

struct TripIslandLeading: View {
    let context: ActivityViewContext<TripAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(context.attributes.fromName + " → " + context.attributes.toName)
                .font(.headline)
                .lineLimit(1)
            if !context.attributes.lineName.isEmpty {
                Text(context.attributes.lineName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct TripIslandTrailing: View {
    let context: ActivityViewContext<TripAttributes>
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(context.state.arrivalDate, style: .timer)
                .font(.headline)
                .monospacedDigit()
            Text(stopsText(context.attributes.stopsFormat, context.state.remainingStops))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct TripIslandBottom: View {
    let context: ActivityViewContext<TripAttributes>
    var body: some View {
        HStack {
            Label(context.attributes.nextLabel + " " + context.state.nextStation, systemImage: "tram.fill")
                .font(.subheadline)
            Spacer()
            Text(context.attributes.tripLabel)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
