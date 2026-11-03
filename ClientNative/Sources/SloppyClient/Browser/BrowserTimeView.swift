import SwiftUI
import Charts
import SloppyClientUI

@MainActor
struct BrowserTimeView: View {
    let state: BrowserWorkspaceState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.browserSidebarLayout) private var isSidebar
    @State private var localDrafts = BrowserSidebarDrafts()
    @State private var siteError: String?
    @State private var clearsUsage = false
    @FocusState private var isDomainFocused: Bool

    private var drafts: BrowserSidebarDrafts { isSidebar ? state.sidebarDrafts : localDrafts }
    private var week: Bool {
        get { drafts.timeWeek }
        nonmutating set { drafts.timeWeek = newValue }
    }
    private var siteDraft: String {
        get { drafts.timeSite }
        nonmutating set { drafts.timeSite = newValue }
    }

    private var time: BrowserTimeStore { state.time }
    private var range: DateInterval { time.interval(week: week) }
    private var siteTimes: [BrowserSiteTime] { time.sites(in: range) }
    private var configuredHosts: [String] { Set(time.siteLimits.keys).union(time.focusSites).sorted() }
    private var recentPages: [WorkspaceBrowserRecentSite] {
        state.history.sites.filter { site in
            guard let date = site.lastVisitedAt else { return false }
            return date >= range.start && date < range.end
        }
    }

    var body: some View {
        Group {
            if isSidebar { timeContent }
            else {
                NavigationStack {
                    timeContent
                        .navigationTitle("Time & Focus")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: isSidebar ? nil : 520, idealWidth: isSidebar ? nil : 620,
               minHeight: isSidebar ? nil : 560, idealHeight: isSidebar ? nil : 780)
#else
        .presentationDetents([.large])
#endif
#if os(iOS)
        .tint(.blue)
#endif
        .task {
            guard !isSidebar else { return }
            state.setTimeTrackingActive(false)
            while !Task.isCancelled {
                time.updateClock()
                state.updateTimeUsage()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-time-screen")
    }

    private var timeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if isSidebar { Text("Time & Focus").font(.headline) }
                periodPicker
                usageSummary
                focusPanel
                limits
                sites
                visitedPages
                VStack(alignment: .leading, spacing: 10) {
                    Label("Counted on this device only", systemImage: "lock")
                    Text("Only the selected website in the active Sloppy browser window counts. Background tabs, other apps and time away from Sloppy are excluded.")
                    Text("Limits pause websites inside Sloppy. You can change them here at any time. Usage is kept for 35 days; clearing browsing history does not clear time totals.")
                    Button("Clear time statistics", role: .destructive) { clearsUsage = true }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(isSidebar ? 12 : 24)
            .frame(maxWidth: 660)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.background)
        .confirmationDialog("Clear time statistics on this device?", isPresented: $clearsUsage) {
            Button("Clear statistics", role: .destructive) { time.clearUsage(); state.updateTimeUsage() }
        } message: { Text("Your browsing history, timer and limits will be kept.") }
    }

    private var periodPicker: some View {
        Group {
#if os(macOS)
            BrowserTimePeriodPicker(week: Binding(get: { week }, set: { week = $0 }))
#else
            Picker("Period", selection: Binding(get: { week }, set: { week = $0 })) {
                Text("Today").tag(false)
                Text("This week").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
#endif
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("browser-time-period")
    }

    private var usageSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.duration(time.total(in: range))).font(.system(size: 42, weight: .semibold))
                .contentTransition(.numericText())
            Text("active on the web").foregroundStyle(.secondary)
            let bars = time.chart(week: week)
            Chart(Array(bars.enumerated()), id: \.offset) { item in
                BarMark(x: .value("Period", item.offset), y: .value("Minutes", item.element / 60))
                    .foregroundStyle(theme.colors.textSecondary.opacity(0.55))
                    .cornerRadius(3)
            }
            .chartYScale(domain: 0...max(1, (bars.max() ?? 0) / 60))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: Array(stride(from: 0, to: bars.count, by: week ? 1 : 6))) { value in
                    AxisValueLabel {
                        if let index = value.as(Int.self) {
                            if let date = time.calendar.date(byAdding: week ? .day : .hour, value: index, to: range.start) {
                                Text(date, format: week ? .dateTime.weekday(.abbreviated) : .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                            }
                        }
                    }
                }
            }
            .frame(height: 116)
            .padding(.top, 8)
        }
    }

    private var focusPanel: some View {
        let layout = isSidebar
            ? AnyLayout(VStackLayout(alignment: .center, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 24))
        return layout {
            ZStack {
                Circle().stroke(theme.colors.border, lineWidth: 7)
                Circle().trim(from: 0, to: time.progress)
                    .stroke(theme.colors.textPrimary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(timerText).font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
            }
            .frame(width: 116, height: 116)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(time.phase == .rest ? "Break" : "Focus"), \(Int(time.remaining.rounded(.up))) seconds remaining")
            VStack(alignment: isSidebar ? .center : .leading, spacing: 10) {
                Text(time.phase == .rest ? "Take a break" : "Pomodoro").font(.title2.weight(.semibold))
                Text(time.isPaused ? "Paused" : "\(time.focusSites.count) \(time.focusSites.count == 1 ? "site" : "sites") paused during focus")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    if time.phase == .ready {
                        Button("Start focus") { time.startFocus(); state.updateTimeUsage() }
                            .accessibilityIdentifier("browser-focus-start")
                    } else {
                        Button(time.isPaused ? "Resume" : "Pause") { time.togglePause(); state.updateTimeUsage() }
                        Button("End") { time.stopFocus(); state.updateTimeUsage() }
#if os(macOS)
                            .buttonStyle(.glass)
#else
                            .buttonStyle(.bordered)
#endif
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                Text("\(time.completedSessions) completed sessions").font(.caption).foregroundStyle(.secondary)
            }
            if !isSidebar { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: isSidebar ? .center : .leading)
        .padding(isSidebar ? 12 : 20)
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(theme.colors.border) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-focus-panel")
    }

    private var timerText: String {
        let seconds = Int(time.remaining.rounded(.up))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Timer") {
                VStack(spacing: 12) {
                    Stepper(value: Binding(get: { time.focusMinutes }, set: {
                        time.configureFocus(minutes: $0, breakMinutes: time.breakMinutes)
                    }), in: 1...120, step: 5) {
                        settingLabel("Focus", value: "\(time.focusMinutes) min")
                    }
                    Divider()
                    Stepper(value: Binding(get: { time.breakMinutes }, set: {
                        time.configureFocus(minutes: time.focusMinutes, breakMinutes: $0)
                    }), in: 1...30) {
                        settingLabel("Break", value: "\(time.breakMinutes) min")
                    }
                }
                .disabled(time.phase != .ready)
                .padding(4)
            }
            GroupBox("Daily limit") {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper(value: Binding(get: { time.dailyLimitMinutes }, set: {
                        time.setDailyLimit($0); state.updateTimeUsage()
                    }), in: 0...1440, step: 15) {
                        settingLabel("Browser", value: time.dailyLimitMinutes == 0 ? "Off" : "\(time.dailyLimitMinutes) min")
                    }
                    Text("Resets at midnight.").font(.caption).foregroundStyle(.secondary)
                }.padding(4)
            }
            Text("Websites").font(.headline)
            Text("Pause sites during focus or set a daily limit. Rules include subdomains.")
                .font(.caption).foregroundStyle(.secondary)
            domainEntry
            if let siteError { Text(siteError).font(.caption).foregroundStyle(.red) }
            configuredSiteRules
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingLabel(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
    }

    private var domainField: some View {
        TextField("Website domain", text: Binding(get: { siteDraft }, set: { siteDraft = $0 }), prompt: Text("example.com"))
            .textFieldStyle(.plain)
            .focused($isDomainFocused)
            .autocorrectionDisabled()
#if os(macOS)
            .textInputSuggestions {
                ForEach(BrowserDomainSuggestions.hosts(query: siteDraft, history: state.history.sites,
                    excluding: Set(configuredHosts)), id: \.self) { host in
                    Text(host).textInputCompletion(host)
                }
            }
#elseif os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .submitLabel(.done)
#endif
            .onSubmit(addSite)
            .accessibilityLabel("Website domain")
            .accessibilityIdentifier("browser-time-domain")
    }

    private var domainEntry: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                    domainField
                }
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular.interactive(), in: Capsule())
                Button("Add site", systemImage: "plus", action: addSite)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .disabled(siteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Add site")
                    .accessibilityIdentifier("browser-time-add-site")
            }
        }
    }

    private var configuredSiteRules: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(configuredHosts, id: \.self) { host in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(host).font(.body.weight(.medium)).lineLimit(1)
                        Spacer()
                        Button { time.setSiteLimit(host: host, minutes: 0); time.setFocusSite(host, enabled: false); state.updateTimeUsage() } label: {
                            Image(systemName: "trash")
                        }.accessibilityLabel("Remove rules for \(host)")
                    }
                    Toggle("Pause during focus", isOn: Binding(get: { time.focusSites.contains(host) }, set: {
                        time.setFocusSite(host, enabled: $0); state.updateTimeUsage()
                    }))
                    let minutes = time.siteLimits[host] ?? 0
                    Stepper(minutes == 0 ? "Daily limit: Off" : "Daily limit: \(minutes) min",
                            value: Binding(get: { time.siteLimits[host] ?? 0 }, set: { time.setSiteLimit(host: host, minutes: $0); state.updateTimeUsage() }),
                            in: 0...1440, step: 5)
                    Divider()
                }
            }
        }
    }

    private var sites: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sites").font(.headline)
            if siteTimes.isEmpty {
                Text("No website time recorded for this period yet.").foregroundStyle(.secondary)
            }
            ForEach(siteTimes) { site in
                VStack(spacing: 8) {
                    HStack {
                        Text(site.host).lineLimit(1)
                        Spacer()
                        Text(Self.duration(site.seconds)).foregroundStyle(.secondary)
                        Menu {
                            Button("Set 30 min daily limit") { time.setSiteLimit(host: site.host, minutes: 30); state.updateTimeUsage() }
                            Button(time.focusSites.contains(site.host) ? "Allow during focus" : "Pause during focus") {
                                time.setFocusSite(site.host, enabled: !time.focusSites.contains(site.host)); state.updateTimeUsage()
                            }
                        } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("Time rules for \(site.host)")
                    }
                    ProgressView(value: site.seconds, total: max(1, siteTimes.first?.seconds ?? 1))
                        .tint(theme.colors.textSecondary)
                }
            }
        }
    }

    private var visitedPages: some View {
        DisclosureGroup("Visited pages (\(recentPages.count))") {
            VStack(alignment: .leading, spacing: 12) {
                if recentPages.isEmpty { Text("No visits recorded for this period.").foregroundStyle(.secondary) }
                ForEach(recentPages) { site in
                    Button {
                        state.open(site.url, inNewTab: true)
                        if !isSidebar { dismiss() }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(site.title).lineLimit(1)
                            Text(site.url.absoluteString).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                            if let date = site.lastVisitedAt {
                                Text(date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }.padding(.top, 12)
        }
    }

    private func addSite() {
        guard let host = BrowserTimeStore.normalizedHost(siteDraft), !host.isEmpty, !host.contains(where: \.isWhitespace) else {
            siteError = "Enter a website domain, such as example.com."
            return
        }
        siteError = nil
        time.setFocusSite(host, enabled: true)
        siteDraft = ""
        isDomainFocused = false
        state.updateTimeUsage()
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds)) / 60
        if minutes == 0 { return seconds > 0 ? "<1m" : "0m" }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
