//
//  ScannerStripesOverlay.swift
//  HomeIndex
//
//  SwiftUI view that displays animated diagonal stripes
//  masked by the coverage mask (only showing in unscanned areas).
//

import SwiftUI
import CoreGraphics

struct ScannerStripesOverlay: View {
    /// The coverage mask image (white = uncovered, black = covered)
    let maskImage: CGImage?

    /// Whether the overlay should be visible
    let isVisible: Bool

    /// Animation phase for moving stripes
    @State private var phase: CGFloat = 0

    // Stripe configuration
    private let stripeWidth: CGFloat = 24
    private let stripeColor = Color.red.opacity(0.5)

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                drawStripes(context: context, size: size)
            }
            .mask {
                if let mask = maskImage {
                    // Use the mask image to show stripes only in uncovered areas
                    Image(decorative: mask, scale: 1.0)
                        .resizable()
                        .interpolation(.low)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    // No mask yet = show full stripes (initial state)
                    Color.white
                }
            }
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.5), value: isVisible)
        }
        .allowsHitTesting(false)
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            phase = stripeWidth * 2
        }
    }

    private func drawStripes(context: GraphicsContext, size: CGSize) {
        // Calculate diagonal length to ensure full coverage
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let stripeCount = Int(diagonal / stripeWidth) + 4

        var path = Path()

        // Draw diagonal stripes (top-left to bottom-right)
        for i in -stripeCount...stripeCount {
            let offset = CGFloat(i) * stripeWidth * 2 + phase

            // Create parallelogram for each stripe
            // Starting from above the view, going down-right
            let x0 = offset - size.height
            let x1 = offset
            let x2 = offset + stripeWidth
            let x3 = offset + stripeWidth - size.height

            path.move(to: CGPoint(x: x0, y: 0))
            path.addLine(to: CGPoint(x: x1, y: size.height))
            path.addLine(to: CGPoint(x: x2, y: size.height))
            path.addLine(to: CGPoint(x: x3, y: 0))
            path.closeSubpath()
        }

        context.fill(path, with: .color(stripeColor))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black

        ScannerStripesOverlay(
            maskImage: nil,
            isVisible: true
        )
    }
}
