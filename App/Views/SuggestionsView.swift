import SwiftUI
import StreetTrackerCore

struct SuggestionsView: View {
    let suggestions: [UnwalkedSuggestion]

    var body: some View {
        NavigationStack {
            List(suggestions, id: \.segmentID) { suggestion in
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.name ?? "Ulice bez názvu")
                        .font(.body)
                    HStack {
                        if let district = suggestion.district {
                            Text(district)
                        }
                        Spacer()
                        Text(formattedDistance(suggestion.distanceMeters))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .overlay {
                if suggestions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Zatím žádné návrhy")
                            .font(.headline)
                        Text("Zapni sledování, aby appka znala tvou polohu, a zkus to znovu.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            }
            .navigationTitle("Neprošlé ulice poblíž")
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }
}
