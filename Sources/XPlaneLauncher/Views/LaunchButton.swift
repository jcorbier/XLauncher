import SwiftUI

struct LaunchButton: View {
    @Environment(PluginManager.self) var pluginManager
    
    var body: some View {
        Button(action: {
            pluginManager.launchXPlane()
        }) {
            HStack {
                Image(systemName: "airplane")
                    .rotationEffect(.degrees(-45))
                Text("Launch X-Plane")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.gradient)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 3)
        }
        .buttonStyle(.plain) // Important for custom styling in SwiftUI macOS
        .disabled(pluginManager.xPlanePath == nil)
        .opacity(pluginManager.xPlanePath == nil ? 0.6 : 1.0)
    }
}
