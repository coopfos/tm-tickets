import SwiftUI

struct SignatureStroke: Identifiable, Hashable {
    let id = UUID()
    var points: [CGPoint] = []
    var lineWidth: CGFloat = 2.0

    var isEmpty: Bool { points.isEmpty }
}

struct SignatureCanvas: View {
    @Binding var strokes: [SignatureStroke]
    var isEnabled: Bool = true
    @State private var currentStroke = SignatureStroke(points: [], lineWidth: 2.0)

    private let lineColor: Color = .primary

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // Background hint
                if strokes.isEmpty && currentStroke.isEmpty {
                    Text(isEnabled ? "Sign here" : "Tap Sign to enable")
                        .foregroundStyle(.secondary)
                        .padding(12)
                }

                // Render strokes
                Canvas { context, size in
                    for stroke in strokes + [currentStroke] where !stroke.points.isEmpty {
                        var path = Path()
                        path.addLines(stroke.points)
                        let style = StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
                        context.stroke(path, with: .color(lineColor), style: style)
                    }
                }
                .contentShape(Rectangle())
            }
            .gesture(isEnabled ? drawingGesture(in: proxy.size) : nil)
        }
        .drawingGroup()
    }

    // MARK: - Gesture
    private func drawingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = clampedPoint(value.location, in: size)
                if currentStroke.points.isEmpty {
                    currentStroke.points = [point]
                } else {
                    currentStroke.points.append(point)
                }
            }
            .onEnded { value in
                let point = clampedPoint(value.location, in: size)
                if !currentStroke.points.isEmpty {
                    currentStroke.points.append(point)
                    strokes.append(currentStroke)
                }
                currentStroke = SignatureStroke(points: [], lineWidth: 2.0)
            }
    }

    private func clampedPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, p.x), size.width),
                y: min(max(0, p.y), size.height))
    }
}

#Preview {
    struct Wrapper: View {
        @State var strokes: [SignatureStroke] = []
        var body: some View {
            SignatureCanvas(strokes: $strokes)
                .frame(height: 240)
                .padding()
        }
    }
    return Wrapper()
}
