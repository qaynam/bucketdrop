//
//  ToastView.swift
//  BucketDrop
//
//  A small Raycast-style floating toast shown on success.
//

import SwiftUI

struct ToastView: View {
    let message: String
    var systemImage: String = "checkmark.circle.fill"
    var tint: Color = .green

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(.subheadline).weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 6)
        .fixedSize()
        // Transparent margin so the drop shadow isn't clipped by the window bounds
        .padding(24)
    }
}

#Preview {
    ToastView(message: "Uploaded & link copied")
        .frame(width: 300, height: 120)
}
