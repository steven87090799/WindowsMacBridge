import SwiftUI
import InputSourceSupport

struct InputSourceStatusLabel: View {
    let status: InputSourceStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(status.selectionConfirmed ? Color.green : (status.issue != nil ? Color.orange : Color.secondary))
                .frame(width: 8, height: 8).accessibilityHidden(true)
            Text(status.summary.hasPrefix("● ") ? String(status.summary.dropFirst(2)) : status.summary)
                .font(.headline)
        }.accessibilityElement(children: .combine)
    }
}
