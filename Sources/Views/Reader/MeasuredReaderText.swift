import SwiftUI
import UIKit

/// The same zero-inset TextKit renderer used by the paginator's measurements.
struct MeasuredReaderText: UIViewRepresentable {
    let text: NSAttributedString
    let color: UIColor

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.layoutManager.usesFontLeading = true
        view.adjustsFontForContentSizeCategory = false
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let displayText = NSMutableAttributedString(attributedString: text)
        displayText.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: displayText.length))
        if view.attributedText != displayText { view.attributedText = displayText }
    }
}

struct MeasuredReaderPage: View {
    let page: ReaderPage
    let style: ReaderPageStyle
    let size: CGSize
    let textColor: Color
    let highlightedParagraph: Int?

    private var textWidth: CGFloat { max(1, size.width - style.horizontalInset * 2) }

    var body: some View {
        VStack(alignment: .leading, spacing: style.paragraphSpacing) {
            if let title = page.title {
                let text = style.attributedTitle(title)
                MeasuredReaderText(text: text, color: UIColor(textColor))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: style.measuredHeight(of: text, width: textWidth))
            }
            ForEach(page.items) { item in
                let text = style.attributedBody(item.text)
                let highlighted = highlightedParagraph == item.index
                MeasuredReaderText(text: text, color: highlighted ? .systemIndigo : UIColor(textColor))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: style.measuredHeight(of: text, width: textWidth))
                    .background(highlighted ? Color.indigo.opacity(0.10) : Color.clear)
                    .accessibilityLabel(item.text)
            }
        }
        .padding(.horizontal, style.horizontalInset)
        .padding(.vertical, style.verticalInset)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }
}
