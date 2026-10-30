import XCTest
import SwiftUI
import UIKit
@testable import LegadoReader

final class ReaderPagerTests: XCTestCase {
    @MainActor
    func testProgrammaticTurnsExcludeDragsButKeepTapsAndNativeSwipesAvailable() throws {
        let recorder = TransitionRecorder()
        let controller = recorder.makeController()
        configure(controller, selection: 0)
        let pager = try XCTUnwrap(controller.pager)
        let pan = try XCTUnwrap(pager.view.subviews.compactMap { $0 as? UIScrollView }.first?.panGestureRecognizer)
        let tap = try XCTUnwrap(controller.view.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first)
        XCTAssertTrue(pan.isEnabled)
        configure(controller, selection: 1)
        XCTAssertFalse(pan.isEnabled, "A drag must not race the programmatic completion")
        XCTAssertTrue(tap.isEnabled, "Rapid taps must still be accepted")
        configure(controller, selection: 2)
        recorder.requests[0].complete(true)
        XCTAssertFalse(pan.isEnabled, "The queued turn still owns the pager")
        recorder.requests[1].complete(true)
        XCTAssertTrue(pan.isEnabled)

        let current = try XCTUnwrap(pager.viewControllers?.first)
        let next = try XCTUnwrap(controller.pageViewController(pager, viewControllerAfter: current))
        controller.pageViewController(pager, willTransitionTo: [next])
        XCTAssertTrue(pan.isEnabled, "An interactive swipe must keep following the finger")
        controller.pageViewController(pager, didFinishAnimating: true,
                                      previousViewControllers: [current], transitionCompleted: false)
        XCTAssertTrue(pan.isEnabled)
        XCTAssertEqual(controller.visibleIndex, 2)
    }

    @MainActor
    func testTapChangesUseDirectionalAnimationsAndQueueLatestSelection() throws {
        let recorder = TransitionRecorder()
        let controller = recorder.makeController()
        var published: [Int] = []
        configure(controller, selection: 0, onSelection: { published.append($0) })
        configure(controller, selection: 1, onSelection: { published.append($0) })
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertTrue(recorder.requests[0].animated)
        XCTAssertEqual(recorder.requests[0].direction, .forward)
        XCTAssertEqual(controller.visibleIndex, 0)

        // A second/third tap cannot start a competing UIKit transition or be lost to an old completion.
        configure(controller, selection: 2, onSelection: { published.append($0) })
        configure(controller, selection: 3, onSelection: { published.append($0) })
        XCTAssertEqual(recorder.requests.count, 1)
        recorder.requests[0].complete(true)
        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertTrue(controller.isTransitioning)
        recorder.requests[1].complete(true)
        XCTAssertEqual(controller.visibleIndex, 3)

        configure(controller, selection: 2, onSelection: { published.append($0) })
        XCTAssertEqual(recorder.requests.last?.direction, .reverse)
        XCTAssertEqual(recorder.requests.last?.animated, true)
        recorder.requests.last?.complete(true)
        XCTAssertEqual(controller.visibleIndex, 2)
        XCTAssertTrue(published.isEmpty, "Programmatic changes must not publish an old page over a newer speech/tap target")
    }

    @MainActor
    func testRestorationReplacesInFlightAnimationWithoutSlidingOrPublishingOldPage() throws {
        let recorder = TransitionRecorder()
        let controller = recorder.makeController()
        var published: [Int] = []
        configure(controller, selection: 0, onSelection: { published.append($0) })
        let oldPager = try XCTUnwrap(controller.pager)
        configure(controller, selection: 1, onSelection: { published.append($0) })
        configure(controller, selection: 2, animate: false, onSelection: { published.append($0) })
        XCTAssertFalse(controller.pager === oldPager)
        XCTAssertEqual(controller.visibleIndex, 2)
        XCTAssertFalse(controller.isTransitioning)
        XCTAssertEqual(recorder.requests.count, 1)
        recorder.requests[0].complete(true)
        XCTAssertEqual(controller.visibleIndex, 2)
        XCTAssertTrue(published.isEmpty)
    }

    @MainActor
    func testChapterIdentityRejectsOldAnimationAndOldSwipeCallbacks() throws {
        let recorder = TransitionRecorder()
        let controller = recorder.makeController()
        var published: [Int] = []
        configure(controller, selection: 0, onSelection: { published.append($0) })
        let oldPager = try XCTUnwrap(controller.pager)
        let oldPage = try XCTUnwrap(oldPager.viewControllers?.first)
        configure(controller, selection: 1, onSelection: { published.append($0) })
        configure(controller, selection: 0, count: 2, identity: "new chapter", onSelection: { published.append($0) })
        recorder.requests[0].complete(true)
        controller.pageViewController(oldPager, willTransitionTo: [oldPage])
        controller.pageViewController(oldPager, didFinishAnimating: true,
                                      previousViewControllers: [oldPage], transitionCompleted: true)
        XCTAssertEqual(controller.visibleIndex, 0)
        XCTAssertFalse(controller.isTransitioning)
        XCTAssertNil(controller.pageViewController(oldPager, viewControllerAfter: oldPage))
        XCTAssertTrue(published.isEmpty)
    }

    @MainActor
    func testCancelledNativeSwipeDoesNotSavePageButCompletedSwipeDoes() throws {
        let recorder = TransitionRecorder()
        let controller = recorder.makeController()
        var published: [Int] = []
        configure(controller, selection: 0, onSelection: { published.append($0) })
        let pager = try XCTUnwrap(controller.pager)
        let first = try XCTUnwrap(pager.viewControllers?.first)
        let second = try XCTUnwrap(controller.pageViewController(pager, viewControllerAfter: first))
        XCTAssertNil(controller.pageViewController(pager, viewControllerBefore: first))
        controller.pageViewController(pager, willTransitionTo: [second])
        controller.pageViewController(pager, didFinishAnimating: true,
                                      previousViewControllers: [first], transitionCompleted: false)
        XCTAssertEqual(controller.visibleIndex, 0)
        XCTAssertTrue(published.isEmpty)

        controller.pageViewController(pager, willTransitionTo: [second])
        pager.setViewControllers([second], direction: .forward, animated: false)
        controller.pageViewController(pager, didFinishAnimating: true,
                                      previousViewControllers: [first], transitionCompleted: true)
        XCTAssertEqual(controller.visibleIndex, 1)
        XCTAssertEqual(published, [1])
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    @MainActor
    func testNativeSwipeCannotOverwriteTargetChangedBySpeechOrTapDuringDrag() throws {
        let recorder = TransitionRecorder()
        let controller = recorder.makeController()
        var published: [Int] = []
        configure(controller, selection: 0, onSelection: { published.append($0) })
        let pager = try XCTUnwrap(controller.pager)
        let first = try XCTUnwrap(pager.viewControllers?.first)
        let second = try XCTUnwrap(controller.pageViewController(pager, viewControllerAfter: first))
        controller.pageViewController(pager, willTransitionTo: [second])
        configure(controller, selection: 3, onSelection: { published.append($0) })
        pager.setViewControllers([second], direction: .forward, animated: false)
        controller.pageViewController(pager, didFinishAnimating: true,
                                      previousViewControllers: [first], transitionCompleted: true)
        XCTAssertTrue(published.isEmpty)
        XCTAssertEqual(recorder.requests.count, 1)
        recorder.requests[0].complete(true)
        XCTAssertEqual(controller.visibleIndex, 3)
    }

    @MainActor
    func testEmptyChapterAndOutOfBoundsSelectionCannotBuildInvalidPage() {
        let controller = ReaderPagerController()
        var built: [Int] = []
        controller.configure(count: 0, selection: 200, identity: "empty", animateChanges: true,
                             page: { built.append($0); return AnyView(Color.clear) }, onSelection: { _ in })
        XCTAssertNil(controller.visibleIndex)
        XCTAssertTrue(built.isEmpty)
        controller.configure(count: 2, selection: 200, identity: "loaded", animateChanges: true,
                             page: { built.append($0); return AnyView(Color.clear) }, onSelection: { _ in })
        XCTAssertEqual(controller.visibleIndex, 1)
        XCTAssertTrue(built.allSatisfy { (0..<2).contains($0) })
    }

    @MainActor
    func testReduceMotionAvoidsHorizontalAnimationAndNormalRestoreIsNonanimated() {
        let recorder = TransitionRecorder()
        let controller = recorder.makeController()
        configure(controller, selection: 0)
        configure(controller, selection: 1, reduceMotion: true)
        XCTAssertEqual(recorder.requests.last?.animated, false)
        recorder.requests.last?.complete(true)
        configure(controller, selection: 2, animate: false)
        XCTAssertEqual(recorder.requests.last?.animated, false)
        recorder.requests.last?.complete(true)
        XCTAssertEqual(controller.visibleIndex, 2)
    }

    @MainActor
    func testMountedNativePagerHasVisibleIntermediateMovement() async throws {
        let controller = ReaderPagerController()
        configure(controller, selection: 0)
        let mounted = mount(controller, size: CGSize(width: 600, height: 400))
        defer { mounted.window.isHidden = true; mounted.window.rootViewController = nil; mounted.previousKey?.makeKeyAndVisible() }
        mounted.root.view.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        let pager = try XCTUnwrap(controller.pager)
        let scroll = try XCTUnwrap(pager.view.subviews.compactMap { $0 as? UIScrollView }.first)
        for _ in 0..<5 { try await Task.sleep(nanoseconds: 10_000_000) }
        let initialOffset = scroll.contentOffset.x
        configure(controller, selection: 1)
        XCTAssertTrue(controller.isTransitioning, "Tap-driven change must start a real native animation")
        var observedMovement = false
        for _ in 0..<500 {
            try await Task.sleep(nanoseconds: 10_000_000)
            if controller.isTransitioning && abs(scroll.contentOffset.x - initialOffset) > 1 {
                observedMovement = true
            }
            if !controller.isTransitioning { break }
        }
        XCTAssertTrue(observedMovement, "A mounted page must visibly travel between its start and finish, rather than replace text instantly")
        XCTAssertFalse(controller.isTransitioning)
        XCTAssertEqual(controller.visibleIndex, 1)
    }

    @MainActor
    func testPagerHostKeepsMeasuredTextWithinAvailablePage() async throws {
        for width in [CGFloat(235), CGFloat(430)] {
            let size = CGSize(width: width, height: 390)
            let style = ReaderPageStyle(config: .default)
            let pages = ReaderPaginator.paginate(paragraphs: [String(repeating: "页面容器不能再次扣除安全区。", count: 30)],
                                                 chapterTitle: "第一章", style: style, viewport: size)
            XCTAssertFalse(pages.isEmpty)
            let controller = ReaderPagerController()
            controller.configure(count: pages.count, selection: 0, identity: width, animateChanges: false,
                                 page: { AnyView(MeasuredReaderPage(page: pages[$0], style: style, size: size,
                                                                   textColor: .black, highlightedParagraph: nil)) },
                                 onSelection: { _ in })
            let mounted = mount(controller, size: size)
            defer { mounted.window.isHidden = true; mounted.window.rootViewController = nil; mounted.previousKey?.makeKeyAndVisible() }
            for _ in 0..<100 {
                mounted.root.view.layoutIfNeeded()
                controller.view.layoutIfNeeded()
                if !descendants(of: controller.view).compactMap({ $0 as? UITextView }).isEmpty { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let pageView = try XCTUnwrap(controller.pager?.viewControllers?.first?.view)
            let texts = descendants(of: pageView).compactMap { $0 as? UITextView }
            XCTAssertFalse(texts.isEmpty)
            for text in texts {
                let frame = text.convert(text.bounds, to: controller.view)
                XCTAssertGreaterThanOrEqual(frame.minX, -1)
                XCTAssertGreaterThanOrEqual(frame.minY, -1)
                XCTAssertLessThanOrEqual(frame.maxX, size.width + 1)
                XCTAssertLessThanOrEqual(frame.maxY, size.height + 1)
                XCTAssertLessThanOrEqual(ceil(text.sizeThatFits(CGSize(width: text.bounds.width, height: .greatestFiniteMagnitude)).height), text.bounds.height + 1)
            }
        }
    }

    @MainActor
    private func configure(_ controller: ReaderPagerController, selection: Int, count: Int = 4,
                           identity: AnyHashable = "chapter", animate: Bool = true, reduceMotion: Bool = false,
                           onSelection: @escaping (Int) -> Void = { _ in }) {
        controller.configure(count: count, selection: selection, identity: identity,
                             animateChanges: animate, reduceMotion: reduceMotion,
                             page: { AnyView(Text("Page \($0)").frame(maxWidth: .infinity, maxHeight: .infinity)) },
                             onSelection: onSelection)
    }

    @MainActor
    private func mount(_ controller: UIViewController, size: CGSize) -> (window: UIWindow, root: UIViewController, previousKey: UIWindow?) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previousKey = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(origin: .zero, size: size))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.addChild(controller)
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        controller.view.frame = CGRect(origin: .zero, size: size)
        return (window, root, previousKey)
    }

    @MainActor
    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor
    private final class TransitionRecorder {
        struct Request {
            let direction: UIPageViewController.NavigationDirection
            let animated: Bool
            let complete: (Bool) -> Void
        }
        var requests: [Request] = []

        func makeController() -> ReaderPagerController {
            ReaderPagerController { [self] pager, target, direction, animated, completion in
                pager.setViewControllers([target], direction: direction, animated: false)
                requests.append(Request(direction: direction, animated: animated, complete: completion))
            }
        }
    }
}
