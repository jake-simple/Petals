import SwiftUI

// MARK: - Data Loader

enum SFSymbolCatalog {
    private static let bundlePath = "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle"

    struct Category {
        let key: String
        let icon: String
        var displayName: String { Self.displayNames[key] ?? key }

        private static let displayNames: [String: String] = [
            "whatsnew": "새로운 항목",
            "draw": "그리기",
            "variable": "가변",
            "multicolor": "다색",
            "communication": "커뮤니케이션",
            "weather": "날씨",
            "maps": "지도",
            "objectsandtools": "물체 및 도구",
            "devices": "기기",
            "cameraandphotos": "카메라 및 사진",
            "gaming": "게임",
            "connectivity": "연결",
            "transportation": "교통",
            "automotive": "자동차",
            "accessibility": "손쉬운 사용",
            "privacyandsecurity": "개인 정보 및 보안",
            "human": "사람",
            "home": "홈",
            "fitness": "피트니스",
            "nature": "자연",
            "editing": "편집",
            "textformatting": "텍스트 포맷",
            "media": "미디어",
            "keyboard": "키보드",
            "commerce": "상거래",
            "time": "시간",
            "health": "건강",
            "shapes": "도형",
            "arrows": "화살표",
            "indices": "색인",
            "math": "수학",
        ]
    }

    /// Ordered list of categories (excluding "all")
    static let categories: [Category] = {
        guard let bundle = Bundle(path: bundlePath),
              let url = bundle.url(forResource: "categories", withExtension: "plist", subdirectory: nil)
                ?? bundle.url(forResource: "categories", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let arr = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: String]] else {
            return []
        }
        return arr.compactMap { dict in
            guard let key = dict["key"], let icon = dict["icon"], key != "all" else { return nil }
            return Category(key: key, icon: icon)
        }
    }()

    /// symbol_order.plist → ordered array of all symbol names
    private static let symbolOrder: [String] = {
        guard let bundle = Bundle(path: bundlePath),
              let url = bundle.url(forResource: "symbol_order", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let arr = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] else {
            return []
        }
        return arr
    }()

    /// Index for fast ordering lookups
    private static let orderIndex: [String: Int] = {
        var dict = [String: Int]()
        for (i, name) in symbolOrder.enumerated() {
            dict[name] = i
        }
        return dict
    }()

    /// category key → [symbol names] (ordered by symbol_order)
    static let symbolsByCategory: [String: [String]] = {
        guard let bundle = Bundle(path: bundlePath),
              let url = bundle.url(forResource: "symbol_categories", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] else {
            return [:]
        }
        // Reverse map: symbol → [categories] to category → [symbols]
        var result = [String: [String]]()
        for (symbol, cats) in dict {
            for cat in cats {
                result[cat, default: []].append(symbol)
            }
        }
        // Sort each category's symbols by symbol_order
        let idx = orderIndex
        for key in result.keys {
            result[key]?.sort { (idx[$0] ?? Int.max) < (idx[$1] ?? Int.max) }
        }
        return result
    }()

    /// symbol name → search keywords
    static let searchKeywords: [String: [String]] = {
        guard let bundle = Bundle(path: bundlePath),
              let url = bundle.url(forResource: "symbol_search", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] else {
            return [:]
        }
        return dict
    }()

    /// Search symbols by name and keywords
    static func search(_ query: String) -> [String] {
        let q = query.lowercased()
        return symbolOrder.filter { name in
            if name.localizedCaseInsensitiveContains(q) { return true }
            if let keywords = searchKeywords[name] {
                return keywords.contains { $0.localizedCaseInsensitiveContains(q) }
            }
            return false
        }
    }
}

// MARK: - Picker View

struct SFSymbolPicker: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: SFSymbolCatalog.Category?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                if let cat = selectedCategory, searchText.isEmpty {
                    Button(action: { selectedCategory = nil }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("카테고리")
                        }
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(cat.displayName)
                        .font(.headline)
                    Spacer()
                } else {
                    Text("심볼 선택")
                        .font(.headline)
                    Spacer()
                }
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Search bar
            TextField("심볼 검색…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            Divider()

            // Content
            if !searchText.isEmpty {
                symbolGrid(symbols: SFSymbolCatalog.search(searchText))
            } else if let cat = selectedCategory {
                symbolGrid(symbols: SFSymbolCatalog.symbolsByCategory[cat.key] ?? [])
            } else {
                categoryGrid
            }
        }
        .frame(width: 660, height: 720)
    }

    // MARK: - Category Grid

    private var categoryGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(SFSymbolCatalog.categories, id: \.key) { cat in
                    Button {
                        selectedCategory = cat
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 32))
                                .frame(height: 40)
                            Text(cat.displayName)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
    }

    // MARK: - Symbol Grid

    private func symbolGrid(symbols: [String]) -> some View {
        Group {
            if symbols.isEmpty {
                VStack {
                    Spacer()
                    Text("결과 없음")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(symbols.prefix(500), id: \.self) { name in
                            Button {
                                onSelect(name)
                            } label: {
                                Image(systemName: name)
                                    .font(.system(size: 34))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
}
