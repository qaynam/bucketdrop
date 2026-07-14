//
//  ErrorDetailView.swift
//  BucketDrop
//
//  Shows the full details of an error in a small standalone window.
//

import SwiftUI
import AppKit

struct ErrorDetailView: View {
    let message: String

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Error Details")
                    .font(.headline)
                Spacer()
            }

            ScrollView {
                Text(message.isEmpty ? "No additional details available." : message)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                    withAnimation { didCopy = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation { didCopy = false }
                    }
                } label: {
                    Label(didCopy ? "Copied!" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }

                Spacer()

                Button("Close") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440, height: 320)
    }
}

#Preview {
    ErrorDetailView(message: "Upload failed: 413 - Request Entity Too Large\n\nphoto.png: The request timed out.")
}
