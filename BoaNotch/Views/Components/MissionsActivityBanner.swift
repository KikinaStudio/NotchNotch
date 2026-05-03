import SwiftUI

/// Top-of-tab banner for the Brain panel's Missions tab.
/// Three side-by-side micro-cards reading from Hermes-native data only:
///   - 30-day USD cost (state.db sessions, with month-end forecast)
///   - 7-day session sparkline (state.db sessions)
///   - 7-day cron health (CronStore in-memory)
/// No REST, no log parsing, no FX conversion. USD shown natively because
/// Hermes stores USD; converting to EUR would mean either a stale fixed
/// rate or a network call.
/// Visual language: depth-by-fill (`.quaternary.opacity(0.6)`) consistent
/// with Tools tab Zone 2. No `.glassEffect()` — the panel already has
/// glass behind the gradient on macOS 26+; doubling the material muddies
/// the surface. "Varié" comes from the three rendered centerpieces
/// (mono number / Path sparkline / dot+text), not from the material.
struct MissionsActivityBanner: View {
    let cost: Double?
    let forecast: Double?
    let dailyCounts: [Int]
    let failures: Int
    let healthyJobs: Int

    private var isEmpty: Bool {
        cost == nil
            && dailyCounts.allSatisfy { $0 == 0 }
            && healthyJobs == 0
            && failures == 0
    }

    var body: some View {
        if isEmpty {
            Text("Pas encore d'activité — utilise Hermes quelques jours pour voir tes métriques ici.")
                .font(DS.Text.micro)
                .foregroundStyle(DS.Surface.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else {
            HStack(spacing: 8) {
                CostCard(cost: cost, forecast: forecast)
                SparklineCard(dailyCounts: dailyCounts)
                HealthCard(failures: failures, healthyJobs: healthyJobs)
            }
            .frame(height: 64)
        }
    }
}

// MARK: - Cards

private struct CostCard: View {
    let cost: Double?
    let forecast: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COÛT 30J")
                .font(DS.Text.sectionHead)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(DS.Surface.tertiary)

            Text(costDisplay)
                .font(DS.Text.titleSmall.monospacedDigit())
                .foregroundStyle(DS.Surface.primary)

            Text(forecastDisplay)
                .font(DS.Text.micro)
                .foregroundStyle(DS.Surface.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardBackground)
    }

    private var costDisplay: String {
        guard let c = cost else { return "—" }
        return String(format: "$%.2f", c)
    }

    private var forecastDisplay: String {
        guard let f = forecast else { return "—" }
        return String(format: "$%.2f mois prév.", f)
    }
}

private struct SparklineCard: View {
    let dailyCounts: [Int]

    private var totalSessions: Int { dailyCounts.reduce(0, +) }
    private var avgPerDay: Int {
        guard !dailyCounts.isEmpty else { return 0 }
        return totalSessions / dailyCounts.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ACTIVITÉ 7J")
                .font(DS.Text.sectionHead)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(DS.Surface.tertiary)

            sparkline
                .frame(height: 18)

            Text(subtitleDisplay)
                .font(DS.Text.micro)
                .foregroundStyle(DS.Surface.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardBackground)
    }

    @ViewBuilder
    private var sparkline: some View {
        if totalSessions == 0 || dailyCounts.count < 2 {
            // Empty / insufficient data — leave the slot blank, the subtitle
            // already says "—".
            Color.clear
        } else {
            GeometryReader { geo in
                let peak = max(dailyCounts.max() ?? 1, 1)
                let stepX = geo.size.width / CGFloat(dailyCounts.count - 1)
                Path { path in
                    for (i, value) in dailyCounts.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = geo.size.height - (CGFloat(value) / CGFloat(peak)) * geo.size.height
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    AppColors.accent.opacity(0.8),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private var subtitleDisplay: String {
        if totalSessions == 0 { return "—" }
        return "\(avgPerDay) sessions/j (moy)"
    }
}

private struct HealthCard: View {
    let failures: Int
    let healthyJobs: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SANTÉ 7J")
                .font(DS.Text.sectionHead)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(DS.Surface.tertiary)

            HStack(spacing: 6) {
                Circle()
                    .fill(dotStyle)
                    .frame(width: 6, height: 6)
                Text(headlineDisplay)
                    .font(DS.Text.bodySmall)
                    .foregroundStyle(DS.Surface.primary)
                    .lineLimit(1)
            }

            Text(subtitleDisplay)
                .font(DS.Text.micro)
                .foregroundStyle(DS.Surface.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardBackground)
    }

    private var dotStyle: AnyShapeStyle {
        if failures == 0 && healthyJobs > 0 { return DS.Status.success }
        if failures == 0 && healthyJobs == 0 { return DS.Surface.tertiary }
        if failures <= 3 { return AnyShapeStyle(Color.orange.opacity(0.85)) }
        return DS.Status.failure
    }

    private var headlineDisplay: String {
        if failures == 0 && healthyJobs > 0 { return "Tout va bien" }
        if failures == 0 && healthyJobs == 0 { return "Aucune routine" }
        if failures == 1 { return "1 échec" }
        return "\(failures) échecs"
    }

    private var subtitleDisplay: String {
        if healthyJobs == 0 { return "—" }
        if healthyJobs == 1 { return "1 routine OK" }
        return "\(healthyJobs) routines OK"
    }
}

// MARK: - Shared card surface

/// Same fill as Tools tab Zone 2 cards — keeps the visual rhythm coherent
/// across the panel.
private var cardBackground: some View {
    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        .fill(.quaternary.opacity(0.6))
}
