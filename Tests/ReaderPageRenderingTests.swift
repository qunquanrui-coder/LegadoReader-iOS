import XCTest
import SwiftUI
import UIKit
@testable import LegadoReader

final class ReaderPageRenderingTests: XCTestCase {
    @MainActor
    func testRenderedFragmentsFitAtCoverAndInnerPageWidths() {
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
                controller.loadViewIfNeeded()
                controller.view.frame = CGRect(origin: .zero, size: size)
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
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
