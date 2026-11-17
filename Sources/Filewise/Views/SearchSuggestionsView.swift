import SwiftUI

struct SearchSuggestionsView: View {
    @ObservedObject var library: Library
    let onSelect: (String) -> Void
    private let muted = Color.secondary

    struct SuggestionItem: Identifiable {
        let id = UUID()
        let title: String
        let query: String
        let icon: String
        let color: Color
    }

    private var defaultSuggestions: [SuggestionItem] {
        var items: [SuggestionItem] = [
            SuggestionItem(title: "PDFs from last week", query: "pdf from last week", icon: "doc.text", color: .red),
            SuggestionItem(title: "Recent Screenshots", query: "recent screenshots", icon: "camera.viewfinder", color: .pink),
            SuggestionItem(title: "Large files (> 100 MB)", query: "large", icon: "externaldrive", color: .orange),
            SuggestionItem(title: "Recent downloads", query: "recent downloads", icon: "arrow.down.circle", color: .blue),
            SuggestionItem(title: "Duplicate files", query: "duplicates", icon: "square.on.square", color: .purple),
            SuggestionItem(title: "Modified last week", query: "from last week", icon: "calendar", color: .teal)
        ]

        if let topSource = library.topDownloadSources.first?.key {
            items.append(SuggestionItem(
                title: "Files from \(topSource)",
                query: topSource.lowercased(),
                icon: "network",
                color: .indigo
            ))
        }

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Suggested Filters Section
            VStack(alignment: .leading, spacing: 10) {
                Text("SUGGESTED FILTERS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(muted)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(defaultSuggestions) { suggestion in
                        Button {
                            onSelect(suggestion.query)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: suggestion.icon)
                                    .font(.system(size: 13))
                                    .foregroundStyle(suggestion.color)
                                    .frame(width: 20)

                                Text(suggestion.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Recent Searches Section
            if !library.recentSearches.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("RECENT SEARCHES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(muted)
                        Spacer()
                        Button("Clear") {
                            library.clearRecentSearches()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(muted)
                    }

                    VStack(spacing: 4) {
                        ForEach(library.recentSearches.prefix(5), id: \.self) { search in
                            Button {
                                onSelect(search)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 11))
                                        .foregroundStyle(muted)

                                    Text(search)
                                        .font(.system(size: 12))
                                        .lineLimit(1)

                                    Spacer()

                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 10))
                                        .foregroundStyle(muted)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()

            // Quick Search Tip
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text("Tip: Combine natural terms like “recent pdf” or “large videos”")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 380)
    }
}
