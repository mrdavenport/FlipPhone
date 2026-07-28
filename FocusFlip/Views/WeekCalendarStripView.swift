import Foundation
import SwiftUI

/// Day-centered horizontal pager with **six** visible day columns; the **seventh** column is the fixed calendar control.
/// Strip swipes advance **one week** at a time; the focused day stays centered (slot 0) with the large badge (SVG + optional Rive handoff for `matchedGeometryEffect`).
/// Single-day navigation is handled by the bottom sheet swipe / taps (see `FocusTrackingView.shiftFocusedDay`).
struct WeekCalendarStripView: View {
    let sessions: [FocusSession]
    let user: User?
    var isBottomSheetExpanded: Bool
    /// When false, strip omits `matchedGeometryEffect` so collapse does not drive the hero frame from the strip cell.
    var dailyBadgeMatchedGeometryActive: Bool
    /// Shared with `FocusTrackingView` for the hero daily badge `matchedGeometryEffect`.
    var badgeNamespace: Namespace.ID
    /// 0 = handoff Rive only, 1 = SVG only; Rive uses `1 - mix`, SVG uses `mix` (complementary crossfade).
    var stripHandoffCrossfadeMix: Double
    /// Same `flipphone_logo` / inputs as the hero (second instance).
    var stripCenterHandoffRive: () -> AnyView
    let focusedDay: Date
    @Binding var pageSelectionID: String
    let onCalendarTap: () -> Void
    let onBadgeDayTap: (Date) -> Void

    private let calendar = Calendar.current

    /// Horizontal strip paging moves the focused day by this many calendar days per completed swipe.
    private static let stripPageDayStride: Int = 7
    /// Synthetic pull used to animate a smooth badge handoff when selection changes via tap or external swipe.
    @State private var selectionTransitionPull: CGFloat = 0

    private var dayIDs: [String] {
        let today = calendar.startOfDay(for: Date())
        let earliest = sessions
            .map { calendar.startOfDay(for: $0.endTime) }
            .min() ?? today
        var ids: [String] = []
        var cursor = min(earliest, today)
        while cursor <= today {
            ids.append(dayID(for: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            if ids.count > 800 { break }
        }
        if ids.isEmpty {
            ids = [dayID(for: today)]
        }
        return ids
    }

    private var selectionIndex: Int {
        let ids = dayIDs
        if let i = ids.firstIndex(of: pageSelectionID) { return i }
        return max(0, ids.count - 1)
    }

    /// Top strip no longer swipes directly; this pull is now driven by selection-change animation only.
    private var focusPull: CGFloat { selectionTransitionPull }

    /// Trailing column width — matches toolbar calendar control (six day cells share the remaining width).
    private let calendarColumnWidth: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let pagerW = max(geo.size.width - calendarColumnWidth, 1)
            let idx = selectionIndex
            let ids = dayIDs
            let stride = Self.stripPageDayStride
            let prevIdx = idx - stride
            let nextIdx = idx + stride

            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    if prevIdx >= 0, let d = date(fromDayID: ids[prevIdx]) {
                        weekWindow(centerDay: d, focusPull: focusPull)
                            .frame(width: pagerW)
                    }
                    if let d = date(fromDayID: ids[idx]) {
                        weekWindow(centerDay: d, focusPull: focusPull)
                            .frame(width: pagerW)
                    }
                    if nextIdx < ids.count, let d = date(fromDayID: ids[nextIdx]) {
                        weekWindow(centerDay: d, focusPull: focusPull)
                            .frame(width: pagerW)
                    }
                }
                .offset(x: stripLeadingOffset(pageWidth: pagerW, index: idx, dayCount: ids.count))
                .frame(width: pagerW, height: 56, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())

                // Seventh column: fixed calendar (does not scroll with the week pager).
                VStack(spacing: 4) {
                    Text(" ")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .frame(width: calendarColumnWidth, height: 56, alignment: .center)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { onCalendarTap() })
            }
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .onAppear {
            ensureValidSelection()
            syncPageSelectionToFocusedDay()
        }
        .onChange(of: sessions.count) { _, _ in
            ensureValidSelection()
        }
        .onChange(of: focusedDay) { _, _ in
            ensureValidSelection()
            syncPageSelectionToFocusedDay()
        }
        .onChange(of: pageSelectionID) { oldID, newID in
            animateSelectionTransition(from: oldID, to: newID)
        }
    }

    private func animateSelectionTransition(from oldID: String, to newID: String) {
        guard oldID != newID else { return }
        let ids = dayIDs
        guard
            let oldIndex = ids.firstIndex(of: oldID),
            let newIndex = ids.firstIndex(of: newID),
            oldIndex != newIndex
        else { return }

        // Positive pull mirrors a leftward progression through days (newer day).
        let direction: CGFloat = newIndex > oldIndex ? 1 : -1
        selectionTransitionPull = direction * 0.78
        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.16)) {
            selectionTransitionPull = 0
        }
    }

    /// Keeps the pager index aligned with `focusedDay` when the parent updates the calendar anchor.
    private func syncPageSelectionToFocusedDay() {
        let ids = dayIDs
        guard !ids.isEmpty else { return }
        let id = dayID(for: calendar.startOfDay(for: focusedDay))
        guard ids.contains(id) else { return }
        if pageSelectionID != id {
            pageSelectionID = id
        }
    }

    private func ensureValidSelection() {
        let ids = dayIDs
        guard !ids.isEmpty else { return }
        if !ids.contains(pageSelectionID), let last = ids.last {
            pageSelectionID = last
        }
    }

    private func stripLeadingOffset(pageWidth: CGFloat, index: Int, dayCount: Int) -> CGFloat {
        if dayCount <= 1 { return 0 }
        let stride = Self.stripPageDayStride
        let hasPrev = index >= stride
        let hasNext = index + stride < dayCount
        if hasPrev && hasNext { return -pageWidth }
        if hasPrev && !hasNext { return -pageWidth }
        return 0
    }

    @ViewBuilder
    private func weekWindow(centerDay: Date, focusPull: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach((-3...2), id: \.self) { slot in
                if let date = calendar.date(byAdding: .day, value: slot, to: centerDay) {
                    dayCell(for: date, centerDay: centerDay, slot: slot, focusPull: focusPull)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Day cell

    /// Opacity for strip badges by distance from the centered day (slot 0): 100% / 70% / 50% / 35%.
    private func stripBadgeOpacity(forSlot slot: Int) -> Double {
        switch abs(slot) {
        case 0: return 1.0
        case 1: return 0.7
        case 2: return 0.5
        default: return 0.35
        }
    }

    @ViewBuilder
    private func dayCell(for date: Date, centerDay: Date, slot: Int, focusPull: CGFloat) -> some View {
        let isFocused = calendar.isDate(date, inSameDayAs: centerDay)
        let isFuture = date > calendar.startOfDay(for: Date())
        let dayNumber = calendar.component(.day, from: date)
        let milestone = milestoneForDay(date)

        let pull = focusPull
        let centerScale: CGFloat = {
            guard slot == 0 else { return 1 }
            return 1 - 0.14 * min(1, abs(pull))
        }()
        let neighborScale: CGFloat = {
            if slot == 1 && pull > 0 { return 0.86 + 0.14 * min(1, pull) }
            if slot == -1 && pull < 0 { return 0.86 + 0.14 * min(1, -pull) }
            if slot != 0 { return 0.9 }
            return 1
        }()
        /// Slot 0 exists on every off-screen week column too; only the day matching `focusedDay` may use `matchedGeometryEffect` id `dailyBadge`.
        let isHeroHandoffDestination = slot == 0 && calendar.isDate(date, inSameDayAs: focusedDay)

        VStack(spacing: 4) {
            Text(weekdayLetter(for: date))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(isFocused ? .white : .white.opacity(0.4))

            if let milestone, !isFuture {
                unifiedBadge(
                    milestone: milestone,
                    date: date,
                    slot: slot,
                    isFocusedSlot: slot == 0,
                    isHeroHandoffDestination: isHeroHandoffDestination,
                    centerScale: centerScale,
                    neighborScale: neighborScale
                )
                .opacity(stripBadgeOpacity(forSlot: slot))
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { onBadgeDayTap(date) })
            } else if isFocused {
                focusedPlaceholder(
                    date: date,
                    milestone: milestone,
                    centerScale: centerScale,
                    isHeroHandoffDestination: isHeroHandoffDestination
                )
                .opacity(stripBadgeOpacity(forSlot: slot))
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { onBadgeDayTap(date) })
            } else {
                Text("\(dayNumber)")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(isFuture ? .white.opacity(0.2) : .white.opacity(0.55))
                    .frame(width: 30, height: 30)
                    .scaleEffect(neighborScale)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Single badge rendering path for milestone days; focused vs neighbor is only transform.
    @ViewBuilder
    private func unifiedBadge(
        milestone: Milestone,
        date: Date,
        slot: Int,
        isFocusedSlot: Bool,
        isHeroHandoffDestination: Bool,
        centerScale: CGFloat,
        neighborScale: CGFloat
    ) -> some View {
        let base = badgeImage(
            for: milestone,
            isCompleted: true,
            categoryColor: badgeColorForDay(date)
        )
        let scale = isFocusedSlot ? centerScale : neighborScale
        let side: CGFloat = isFocusedSlot ? 40 : 30
        if isFocusedSlot && isHeroHandoffDestination {
            // Fixed frame + clip *before* matchedGeometry so Rive’s intrinsic size can’t blow up the transition rect.
            ZStack {
                stripCenterHandoffRive()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipped()
                    .allowsHitTesting(false)
                    .opacity(1 - stripHandoffCrossfadeMix)
                base
                    .frame(width: side, height: side)
                    .opacity(stripHandoffCrossfadeMix)
            }
            .frame(width: side, height: side)
            .clipped()
            .dailyBadgeMatchedGeometryIfNeeded(
                dailyBadgeMatchedGeometryActive,
                namespace: badgeNamespace,
                isSource: isBottomSheetExpanded
            )
            .scaleEffect(scale)
        } else {
            base
                .frame(width: side, height: side)
                .scaleEffect(scale)
        }
    }

    private func focusedPlaceholder(
        date: Date,
        milestone: Milestone?,
        centerScale: CGFloat,
        isHeroHandoffDestination: Bool
    ) -> some View {
        Group {
            if isHeroHandoffDestination {
                ZStack {
                    stripCenterHandoffRive()
                        .aspectRatio(1, contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipped()
                        .allowsHitTesting(false)
                        .opacity(1 - stripHandoffCrossfadeMix)
                    focusedCellContent(date: date, milestone: milestone)
                        .frame(width: 40, height: 40)
                        .opacity(stripHandoffCrossfadeMix)
                }
                .frame(width: 40, height: 40)
                .clipped()
                .dailyBadgeMatchedGeometryIfNeeded(
                    dailyBadgeMatchedGeometryActive,
                    namespace: badgeNamespace,
                    isSource: isBottomSheetExpanded
                )
                .scaleEffect(centerScale)
            } else {
                focusedCellContent(date: date, milestone: milestone)
                    .frame(width: 40, height: 40)
                    .scaleEffect(centerScale)
            }
        }
    }

    @ViewBuilder
    private func focusedCellContent(date: Date, milestone: Milestone?) -> some View {
        if let milestone {
            badgeImage(
                for: milestone,
                isCompleted: true,
                categoryColor: badgeColorForDay(date)
            )
        } else {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Data helpers

    private func sessionsByDay() -> [Date: [FocusSession]] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.endTime) }
    }

    private func totalTimeForDay(_ day: Date) -> TimeInterval {
        (sessionsByDay()[day] ?? []).reduce(0) { $0 + $1.duration }
    }

    private func milestoneForDay(_ day: Date) -> Milestone? {
        Milestone.dayMilestoneForTotalTime(totalTimeForDay(day))
    }

    private func badgeColorForDay(_ day: Date) -> Color {
        let daySessions = sessionsByDay()[day] ?? []
        return daySessions
            .sorted(by: { $0.duration > $1.duration })
            .first
            .map { $0.category.color }
            ?? Color(red: 1.0, green: 0.84, blue: 0.0)
    }

    private func weekdayLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    // MARK: - Badge image rendering

    private func badgeImage(for milestone: Milestone, isCompleted: Bool, categoryColor: Color) -> some View {
        let badgeName = "badge-\(milestone.label)"
        if let view = loadSVG(named: badgeName, isCompleted: isCompleted, color: categoryColor) {
            return AnyView(view)
        }
        let sanitized = "badge-\(milestone.label.replacingOccurrences(of: "+", with: "plus"))"
        if let view = loadSVG(named: sanitized, isCompleted: isCompleted, color: categoryColor) {
            return AnyView(view)
        }
        return AnyView(
            Image(systemName: milestone.icon)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(isCompleted ? categoryColor : .white.opacity(0.3))
        )
    }

    private func loadSVG(named badgeName: String, isCompleted: Bool, color: Color) -> AnyView? {
        guard let svgString = SVGCache.shared.rawSVG(named: badgeName) else { return nil }
        return AnyView(SVGColorReplacementView(
            svgString: svgString,
            replacementColor: isCompleted ? color : .white,
            isCompleted: isCompleted
        ))
    }

    private func dayID(for date: Date) -> String {
        let d = calendar.startOfDay(for: date)
        let y = calendar.component(.year, from: d)
        let m = calendar.component(.month, from: d)
        let day = calendar.component(.day, from: d)
        return String(format: "%04d-%02d-%02d", y, m, day)
    }

    private func date(fromDayID id: String) -> Date? {
        let parts = id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        guard let d = calendar.date(from: comps) else { return nil }
        return calendar.startOfDay(for: d)
    }
}
