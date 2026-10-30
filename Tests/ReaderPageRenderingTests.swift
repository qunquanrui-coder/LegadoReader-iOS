import XCTest
import SwiftUI
import UIKit
@testable import LegadoReader

final class ReaderPageRenderingTests: XCTestCase {
    @MainActor
    func testRenderedFragmentsFitAtCoverAndInnerPageWidths() async throws {
        let paragraphs = [String(repeating: "分页后每一个字都必须在页面以内。👩🏽‍💻 ", count: 40), "章节最后一段必须保留。"]
        for width in [CGFloat(235), CGFloat(330), CGFloat(430)] {
            let size = CGSize(width: width, height: 390)
            let style = ReaderPageStyle(config: .default)
            let pages = ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: "第一章 完整分页",
                                                  style: style, viewport: size)
            XCTAssertFalse(pages.isEmpty)
            for page in pages {
                let controller = UIHostingController(rootView:
                    MeasuredReaderPage(page: page, style: style, size: size, textColor: .black,
                                       highlightedParagraph: nil).ignoresSafeArea())
                // SwiftUI creates representable subviews after attachment to a visible window.
                // A detached hosting view has no rendered UITextViews to inspect.
                let container = UIViewController()
                let window: UIWindow
                if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                    window = UIWindow(windowScene: scene)
                } else {
                    window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: 900, height: 700)))
                }
                window.rootViewController = container
                window.makeKeyAndVisible()
                container.addChild(controller)
                container.view.addSubview(controller.view)
                controller.didMove(toParent: container)
                controller.view.frame = CGRect(origin: .zero, size: size)
                defer { window.isHidden = true; window.rootViewController = nil }
                for _ in 0..<100 {
                    container.view.layoutIfNeeded()
                    controller.view.layoutIfNeeded()
                    let rendered = descendants(of: controller.view).compactMap { $0 as? UITextView }
                    if rendered.count == page.items.count + (page.title == nil ? 0 : 1),
                       rendered.allSatisfy({ $0.bounds.width > 0 && $0.bounds.height > 0 }) { break }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                let textViews = descendants(of: controller.view).compactMap { $0 as? UITextView }
                XCTAssertEqual(textViews.count, page.items.count + (page.title == nil ? 0 : 1))
                for text in textViews {
                    let frame = text.convert(text.bounds, to: controller.view)
                    XCTAssertGreaterThanOrEqual(frame.minX, -1)
                    XCTAssertGreaterThanOrEqual(frame.minY, -1)
                    XCTAssertLessThanOrEqual(frame.maxX, size.width + 1)
                    XCTAssertLessThanOrEqual(frame.maxY, size.height + 1)
                    let fitted = text.sizeThatFits(CGSize(width: text.bounds.width, height: .greatestFiniteMagnitude))
                    XCTAssertLessThanOrEqual(ceil(fitted.height), text.bounds.height + 1,
                                             "A page fragment must not need hidden scrolling")
                    XCTAssertFalse(text.isScrollEnabled)
                }
            }
        }
    }

    @MainActor
    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
