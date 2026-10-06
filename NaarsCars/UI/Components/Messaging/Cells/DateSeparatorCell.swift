//
//  DateSeparatorCell.swift
//  NaarsCars
//
//  UICollectionViewCell — centered date label in pill
//

import UIKit

/// Collection view cell showing a date separator pill between message groups.
final class DateSeparatorCell: UICollectionViewCell {

    static let reuseIdentifier = "DateSeparatorCell"
    static let fixedHeight: CGFloat = 44

    // MARK: - Subviews

    private let pillView = UIView()
    private let dateLabel = UILabel()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // iMessage draws the time header as plain centred text, no pill.
        pillView.backgroundColor = .clear
        contentView.addSubview(pillView)

        dateLabel.font = .preferredFont(forTextStyle: .caption1)
        dateLabel.textColor = .secondaryLabel
        dateLabel.textAlignment = .center
        pillView.addSubview(dateLabel)
    }

    // MARK: - Configure

    func configure(date: Date) {
        dateLabel.attributedText = Self.attributedHeader(for: date)

        contentView.isAccessibilityElement = true
        contentView.accessibilityLabel = dateLabel.attributedText?.string
        contentView.accessibilityTraits = .header

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = contentView.bounds
        let hPad: CGFloat = 12
        let vPad: CGFloat = 4

        let textSize = dateLabel.sizeThatFits(CGSize(width: b.width - 80, height: 20))
        let pillW = textSize.width + hPad * 2
        let pillH = textSize.height + vPad * 2
        let pillX = (b.width - pillW) / 2
        let pillY = (b.height - pillH) / 2

        pillView.frame = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
        pillView.layer.cornerRadius = pillH / 2
        dateLabel.frame = CGRect(x: hPad, y: vPad, width: textSize.width, height: textSize.height)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        dateLabel.attributedText = nil
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: Self.fixedHeight)
    }

    // MARK: - Date formatting

    /// "Today 3:45 PM" with the day part emphasised, as in iMessage.
    static func attributedHeader(for date: Date) -> NSAttributedString {
        let base = UIFont.preferredFont(forTextStyle: .caption1)
        let boldDescriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor
        let bold = UIFont(descriptor: boldDescriptor, size: 0)
        let result = NSMutableAttributedString(
            string: formatDate(date),
            attributes: [.font: bold, .foregroundColor: UIColor.secondaryLabel]
        )
        result.append(NSAttributedString(
            string: " " + DateFormatters.timeFormatter.string(from: date),
            attributes: [.font: base, .foregroundColor: UIColor.secondaryLabel]
        ))
        return result
    }

    private static func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return "messaging_today".localized
        }
        if calendar.isDateInYesterday(date) {
            return "messaging_yesterday".localized
        }
        // Same week: day name
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return DateFormatters.dayOfWeekFormatter.string(from: date)
        }
        // Same year: MMM d
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return DateFormatters.monthDayFormatter.string(from: date)
        }
        // Different year: MMM d yyyy
        return DateFormatters.monthDayYearFormatter.string(from: date)
    }
}
