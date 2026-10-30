import SwiftUI
import UIKit

/// A native pager animates both tap-driven changes and interactive swipes. SwiftUI's page-style
/// TabView does not consistently animate a programmatic selection change on all supported OSes.
struct AnimatedReaderPager<Content: View>: UIViewControllerRepresentable {
    @Binding var selection: Int
    let count: Int
    let identity: AnyHashable
    let animateChanges: Bool
    var tapMode: ReaderTapMode = .balanced
    let onTap: (ReaderPageTapRegion) -> Void
    var onBoundarySwipe: ((Bool) -> Void)? = nil
    @ViewBuilder let page: (Int) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIViewController(context: Context) -> ReaderPagerController {
        let controller = ReaderPagerController()
        updateUIViewController(controller, context: context)
        return controller
    }

    func updateUIViewController(_ controller: ReaderPagerController, context: Context) {
        controller.configure(count: count, selection: selection, identity: identity,
                             animateChanges: animateChanges, reduceMotion: reduceMotion, tapMode: tapMode,
                             page: { AnyView(page($0)) }, onSelection: { selection = $0 },
                             onTap: onTap, onBoundarySwipe: onBoundarySwipe)
    }

    static func dismantleUIViewController(_ controller: ReaderPagerController, coordinator: ()) {
        controller.invalidate()
    }
}

@MainActor
final class ReaderPagerController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    /// Tests can hold an actual controller transition open to exercise rapid taps and stale callbacks.
    typealias TransitionDriver = (UIPageViewController, UIViewController,
                                 UIPageViewController.NavigationDirection, Bool,
                                 @escaping (Bool) -> Void) -> Void

    private let transitionDriver: TransitionDriver?
    private(set) var pager: UIPageViewController?
    private(set) var visibleIndex: Int?
    private(set) var isTransitioning = false
    private var pageCount = 0
    private var identity: AnyHashable?
    private var generation = UUID()
    private var transitionID = UUID()
    private var requestedSelection = 0
    private var animateChanges = false
    private var reduceMotion = false
    private var tapMode: ReaderTapMode = .balanced
    private var nativeGestureRequest: Int?
    private var boundaryGestureStart: (index: Int, generation: UUID)?
    private var pages: [Int: ReaderHostedPageController] = [:]
    private var makePage: (Int) -> AnyView = { _ in AnyView(EmptyView()) }
    private var onSelection: (Int) -> Void = { _ in }
    private var onTap: (ReaderPageTapRegion) -> Void = { _ in }
    private var onBoundarySwipe: ((Bool) -> Void)?
    private var tapRecognizer: UITapGestureRecognizer?

    init(transitionDriver: TransitionDriver? = nil) {
        self.transitionDriver = transitionDriver
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true
    }

    func configure(count: Int, selection: Int, identity: AnyHashable,
                   animateChanges: Bool, reduceMotion: Bool = false, tapMode: ReaderTapMode = .balanced,
                   page: @escaping (Int) -> AnyView, onSelection: @escaping (Int) -> Void,
                   onTap: @escaping (ReaderPageTapRegion) -> Void = { _ in },
                   onBoundarySwipe: ((Bool) -> Void)? = nil) {
        loadViewIfNeeded()
        self.makePage = page
        self.onSelection = onSelection
        self.onTap = onTap
        self.onBoundarySwipe = onBoundarySwipe
        self.animateChanges = animateChanges
        self.reduceMotion = reduceMotion
        self.tapMode = tapMode
        let count = max(0, count)
        let target = min(max(0, selection), max(0, count - 1))
        requestedSelection = target
        if self.identity != identity || pageCount != count || pager == nil {
            self.identity = identity
            pageCount = count
            replacePager(selection: target)
            return
        }
        // Theme / spoken-paragraph highlighting may change without repagination.
        for (index, controller) in pages { controller.rootView = AnyView(page(index).ignoresSafeArea()) }
        if !animateChanges && isTransitioning {
            // A restoration must immediately replace an in-flight transition, even if its target
            // happens to equal the old visible page. Its completion cannot write into the new view.
            replacePager(selection: target)
        } else {
            drainRequestedSelection()
        }
    }

    func invalidate() {
        generation = UUID()
        transitionID = UUID()
        pager?.delegate = nil
        pager?.dataSource = nil
        onSelection = { _ in }
        onTap = { _ in }
        onBoundarySwipe = nil
    }

    private func replacePager(selection: Int) {
        generation = UUID()
        transitionID = UUID()
        isTransitioning = false
        nativeGestureRequest = nil
        boundaryGestureStart = nil
        pages.removeAll()
        if let tapRecognizer { view.removeGestureRecognizer(tapRecognizer) }
        if let previous = pager {
            previous.delegate = nil
            previous.dataSource = nil
            previous.willMove(toParent: nil)
            previous.view.removeFromSuperview()
            previous.removeFromParent()
        }
        let next = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        next.delegate = self
        next.dataSource = self
        addChild(next)
        view.addSubview(next.view)
        next.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            next.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            next.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            next.view.topAnchor.constraint(equalTo: view.topAnchor),
            next.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        next.didMove(toParent: self)
        next.view.backgroundColor = .clear
        pager = next
        visibleIndex = pageCount > 0 ? selection : nil
        if let page = controller(at: selection) {
            // Initial display, chapter changes, and fold/resize restorations never slide away.
            next.setViewControllers([page], direction: .forward, animated: false)
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        tap.cancelsTouchesInView = false
        if let scroll = next.view.subviews.compactMap({ $0 as? UIScrollView }).first {
            // A tap must wait for the native pan to fail; a transparent SwiftUI overlay would
            // intercept the touches and prevent interactive dragging entirely.
            tap.require(toFail: scroll.panGestureRecognizer)
            scroll.panGestureRecognizer.addTarget(self, action: #selector(didPan(_:)))
        }
        view.addGestureRecognizer(tap)
        tapRecognizer = tap
    }

    private func controller(at index: Int) -> ReaderHostedPageController? {
        guard (0..<pageCount).contains(index) else { return nil }
        if let existing = pages[index] { return existing }
        let controller = ReaderHostedPageController(index: index, generation: generation, rootView: makePage(index))
        pages[index] = controller
        return controller
    }

    private func drainRequestedSelection() {
        guard !isTransitioning, let visibleIndex, visibleIndex != requestedSelection,
              let pager, let target = controller(at: requestedSelection) else { return }
        let targetIndex = requestedSelection
        let direction: UIPageViewController.NavigationDirection = targetIndex > visibleIndex ? .forward : .reverse
        let generation = self.generation
        let transition = UUID()
        transitionID = transition
        isTransitioning = true
        // A native drag must not interrupt a programmatic slide and finish outside its
        // completion token. Keep the root tap active so rapid taps can still queue a target.
        let pan = pager.view.subviews.compactMap { $0 as? UIScrollView }.first?.panGestureRecognizer
        pan?.isEnabled = false
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, self.generation == generation, self.transitionID == transition else { return }
            self.visibleIndex = (pager.viewControllers?.first as? ReaderHostedPageController)?.index ?? targetIndex
            self.isTransitioning = false
            pan?.isEnabled = true
            self.prunePages()
            // Programmatic changes already came from the binding. Publishing them again could
            // reset a newer tap or a speech paragraph that advanced during the animation.
            self.drainRequestedSelection()
        }
        if let transitionDriver {
            transitionDriver(pager, target, direction, animateChanges && !reduceMotion, completion)
        } else if animateChanges && reduceMotion {
            UIView.transition(with: pager.view, duration: 0.16,
                              options: [.transitionCrossDissolve, .allowAnimatedContent, .beginFromCurrentState],
                              animations: { pager.setViewControllers([target], direction: direction, animated: false) },
                              completion: completion)
        } else {
            pager.setViewControllers([target], direction: direction, animated: animateChanges, completion: completion)
        }
    }

    private func prunePages() {
        guard let visibleIndex else { pages.removeAll(); return }
        pages = pages.filter { abs($0.key - visibleIndex) <= 1 || $0.key == requestedSelection }
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard pageViewController === pager, let page = viewController as? ReaderHostedPageController,
              page.generation == generation else { return nil }
        return controller(at: page.index - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard pageViewController === pager, let page = viewController as? ReaderHostedPageController,
              page.generation == generation else { return nil }
        return controller(at: page.index + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            willTransitionTo pendingViewControllers: [UIViewController]) {
        guard pageViewController === pager, !isTransitioning else { return }
        isTransitioning = true
        nativeGestureRequest = requestedSelection
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard pageViewController === pager, let gestureRequest = nativeGestureRequest else { return }
        nativeGestureRequest = nil
        isTransitioning = false
        if completed, let current = pageViewController.viewControllers?.first as? ReaderHostedPageController,
           current.generation == generation {
            visibleIndex = current.index
            if requestedSelection == gestureRequest {
                requestedSelection = current.index
                onSelection(current.index)
            }
        }
        prunePages()
        drainRequestedSelection()
    }

    @objc private func didTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, pageCount > 0, view.bounds.width > 0 else { return }
        handleTap(at: recognizer.location(in: view).x / view.bounds.width)
    }

    func handleTap(at fraction: CGFloat) {
        guard pageCount > 0, fraction.isFinite else { return }
        onTap(tapMode.region(at: fraction))
    }

    @objc private func didPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            if let visibleIndex, visibleIndex == 0 || visibleIndex == pageCount - 1 {
                boundaryGestureStart = (visibleIndex, generation)
            } else { boundaryGestureStart = nil }
        case .ended:
            defer { boundaryGestureStart = nil }
            guard let start = boundaryGestureStart, start.generation == generation,
                  start.index == visibleIndex, requestedSelection == visibleIndex,
                  !isTransitioning else { return }
            let delta = recognizer.translation(in: view)
            guard abs(delta.x) > max(44, view.bounds.width * 0.12), abs(delta.x) > abs(delta.y) else { return }
            if start.index == 0 && delta.x > 0 { onBoundarySwipe?(true) }
            else if start.index == pageCount - 1 && delta.x < 0 { onBoundarySwipe?(false) }
        case .cancelled, .failed: boundaryGestureStart = nil
        default: break
        }
    }
}

@MainActor
private final class ReaderHostedPageController: UIHostingController<AnyView> {
    let index: Int
    let generation: UUID

    init(index: Int, generation: UUID, rootView: AnyView) {
        self.index = index
        self.generation = generation
        super.init(rootView: AnyView(rootView.ignoresSafeArea()))
        if #available(iOS 16.4, *) { safeAreaRegions = [] }
        view.backgroundColor = .clear
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) { return nil }
}
