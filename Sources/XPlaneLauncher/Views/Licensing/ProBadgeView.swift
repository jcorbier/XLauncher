//
//  ProBadgeView.swift
//  XPlaneLauncher
//
//  Premium badge indicator for XLauncher Pro status.
//

import SwiftUI

public struct ProBadgeView: View {
    public var size: CGFloat = 11

    public init(size: CGFloat = 11) {
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill")
                .font(.system(size: size * 0.8, weight: .bold))
            Text("PRO")
                .font(.system(size: size, weight: .black, design: .rounded))
        }
        .foregroundStyle(
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.95, green: 0.6, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.orange.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 0.8)
                )
        )
    }
}
