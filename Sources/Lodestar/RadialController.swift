import AppKit
import Foundation
import RadialCore

/// Owns the radial panel's lifetime and translates model state into view state.
final class RadialController {

    private let store: BookmarkStore
    private var preferences: Preferences
    private var session: RadialSession
    private let panel = RadialPanel()
    private let menuView = RadialMenuView(frame: .zero)
    /// Bumped on every presentation, so a close animation that finishes after the menu was
    /// reopened cannot tear down the new panel.
    private var presentation = 0

    /// Fired when the hotkey is pressed with nothing to show.
    var onEmptyMenu: (() -> Void)?

    init(store: BookmarkStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
        self.session = RadialSession(paging: store.paging)

        panel.contentView = menuView
        menuView.onActivate = { [weak self] bookmark in
            self?.activate(bookmark)
        }
        menuView.onClose = { [weak self] in
            self?.dismiss()
        }
        menuView.onClickOutside = { [weak self] in
            self?.dismiss()
        }

        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.session.isOpen, event.window === self.panel else { return event }
            return self.handleKey(event)
        }
    }

    var isOpen: Bool { session.isOpen }

    /// Settings can change while the app runs; keep the ring in sync with them.
    func updatePreferences(_ newPreferences: Preferences) {
        preferences = newPreferences
    }

    func present() {
        session.update(paging: store.paging)
        let outcome = session.toggle(hotkeyRepeated: false)
        guard case .opened(let page) = outcome else {
            if outcome == .needsMoreBookmarks { onEmptyMenu?() }
            return
        }
        show(page: page)
    }

    private func show(page: Int) {
        preferences.clamp()
        let screen = ScreenGeometry.activeScreen()
        let pointer = ScreenGeometry.pointerInView(screen)

        // An open compass is a tall object: the lid, a pan with real depth, stands a full diameter
        // above the hinge and the lanyard bow hangs below, so it needs about 4.4 card-radii of
        // height against the old dial's 1.1. The radius setting is an upper bound, not a promise — fitting it to the
        // screen beats hanging the lid off the edge, and `fitted(toHeight:)` keeps its own floor
        // so the numerals stay readable.
        let available = screen.frame.height - 24
        let fitted = CompassMetrics(cardRadius: CGFloat(preferences.menuRadius))
            .fitted(toHeight: available)
        let metrics = fitted
        menuView.configure(
            bookmarks: store.bookmarks(onPage: page),
            page: page,
            paging: store.paging,
            showsNumbers: preferences.showNumbers,
            radius: metrics.cardRadius
        )

        // Horizontal requirement: the case plus a little air.
        let sideMargin = metrics.caseRadius + 14
        // Vertical: the lid above, the lanyard bow and the hint row below.
        let topMargin = metrics.lidReach() + 10
        let bottomMargin = metrics.lugReach + 62

        let centerX = screen.frame.width > sideMargin * 2
            ? min(max(pointer.x, sideMargin), screen.frame.width - sideMargin)
            : screen.frame.width / 2
        let centerY = screen.frame.height > topMargin + bottomMargin
            ? min(max(pointer.y, topMargin), screen.frame.height - bottomMargin)
            : screen.frame.height / 2
        let ringCenter = CGPoint(x: centerX, y: centerY)
        menuView.ringCenter = ringCenter

        // The overlay covers the whole screen so a click anywhere outside the ring dismisses it.
        let frame = CGRect(origin: screen.frame.origin, size: screen.frame.size)
        panel.setFrame(frame, display: true)
        menuView.frame = CGRect(origin: .zero, size: screen.frame.size)
        menuView.layoutSubtreeIfNeeded()

        presentation += 1
        // The app is deliberately not activated: the nonactivating panel takes key focus on its
        // own, so the app you were in stays frontmost and keeps its menu bar. It also means no
        // Stage Manager stage change, on open or on close.
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(menuView)
        menuView.present()
    }

    func dismiss() {
        guard session.isOpen else { return }
        _ = session.close()
        finishAfterClose()
    }

    private func finishAfterClose() {
        let generation = presentation
        menuView.dismiss(animated: true) { [weak self] in
            guard let self, self.presentation == generation else { return }
            self.tearDown()
        }
    }

    private func tearDown() {
        // The other app never lost active status, so ordering out returns the keyboard to it.
        panel.orderOut(nil)

        // Lodestar can already be the active app when summoned, such as just after its manager
        // window closed. With no window of its own left, step down rather than stay active with
        // an empty stage, which makes Stage Manager switch stages. This has to come after
        // `orderOut`, and an open manager window is left alone because it is the right place to land.
        // The level check skips the menu bar item's window, which is always visible in this list.
        if NSApp.isActive, !NSApp.windows.contains(where: { $0.isVisible && $0.level < .statusBar }) {
            NSApp.deactivate()
        }
    }

    /// Pointer activation goes through the session too, so both paths agree on state.
    private func activate(_ bookmark: Bookmark) {
        guard session.isOpen else { return }
        _ = session.close()
        open(bookmark)
    }

    private func open(_ bookmark: Bookmark, after delay: TimeInterval = 0) {
        guard let url = Bookmark.normalizedURL(bookmark.url) else { return }
        // Launch before dismissing: the click should feel like it took effect instantly.
        BrowserLauncher.open(
            url,
            plan: OpenPlan.resolve(bookmark, default: preferences.openBehavior, in: preferences.browser),
            browser: preferences.browser
        )
        if delay > 0 {
            // The close belongs to the presentation that took the key. If the menu is summoned again
            // inside the delay, that is a new presentation, and this close must not take it down.
            let generation = presentation
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.presentation == generation else { return }
                self.finishAfterClose()
            }
        } else {
            finishAfterClose()
        }
    }

    private func goToPage(_ page: Int) {
        session.update(paging: store.paging)
        session.setPage(page)
        menuView.updatePage(
            bookmarks: store.bookmarks(onPage: session.page),
            page: session.page,
            paging: store.paging
        )
    }

    /// Returns nil to swallow the event, or the event to pass it on.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // escape
            dismiss()
            return nil
        }
        switch event.keyCode {
        case 123: // left
            goToPage(session.paging.previousPage(from: session.page))
            return nil
        case 124: // right
            goToPage(session.paging.nextPage(from: session.page))
            return nil
        default:
            break
        }
        guard let characters = event.charactersIgnoringModifiers, let character = characters.first else {
            return event
        }
        // RadialSession owns the "which slice does this key mean" rule (and it is unit tested).
        // Anything it does not claim (⌘Q, Tab, …) must still reach the system.
        guard case .activated(let bookmark, _) = session.activate(key: character, bookmarks: store.bookmarks) else {
            return event
        }
        // The key and the click should feel like the same action, so the slice springs back
        // before the panel tears down.
        if let index = RadialLayout.sliceIndex(forKey: character) {
            menuView.flashSlice(index)
        }
        open(bookmark, after: 0.09)
        return nil
    }

    /// The hotkey fired while the menu is already open.
    func hotkeyWhileOpen() {
        dismiss()
    }
}
