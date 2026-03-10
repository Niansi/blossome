//
//  FragmentListView.swift
//  blossome
//

import SwiftUI

struct FragmentListView: View {
    @EnvironmentObject var fragmentStore: FragmentStore
    @EnvironmentObject var portfolioStore: PortfolioStore

    @State private var showingPortfolio = false
    @State private var selectedFragmentID: UUID? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if fragmentStore.fragments.isEmpty {
                        EmptyFlowerView(
                            title: "我没有找到关于你的碎片"
                        )
                    } else {
                        List {
                            ForEach(fragmentStore.fragments) { fragment in
                                Button {
                                    selectedFragmentID = fragment.id
                                } label: {
                                    FragmentRowView(fragment: fragment)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            }
                            .onDelete(perform: deleteItems)
                        }
                        .listStyle(.plain)
                    }
                }

                // 浮动新建按钮
                Button {
                    let newFragment = fragmentStore.create()
                    selectedFragmentID = newFragment.id
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 60, height: 60)
                }
                .buttonStyle(.glass)
                .clipShape(Circle())
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("碎片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingPortfolio = true
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationDestination(isPresented: $showingPortfolio) {
                PortfolioView()
                    .environmentObject(portfolioStore)
            }
            .navigationDestination(item: $selectedFragmentID) { fragmentID in
                ContentView(fragmentID: fragmentID)
                    .environmentObject(fragmentStore)
                    .environmentObject(portfolioStore)
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let fragment = fragmentStore.fragments[index]
            fragmentStore.delete(id: fragment.id)
        }
    }
}

// MARK: - Fragment Row

struct FragmentRowView: View {
    let fragment: Fragment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fragment.previewTitle)
                .font(.headline)
                .lineLimit(1)

            HStack {
                Text(fragment.updatedAt.fragmentTimeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let body = fragment.previewBody {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Date Formatting Extension

extension Date {
    var fragmentTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: self)
    }
}

// MARK: - Swipeable Delete Row (Custom long-swipe with haptics)

struct SwipeableDeleteModifier: ViewModifier {
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var hasTriggeredHaptic = false
    private let deleteThreshold: CGFloat = -200

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        let translation = value.translation.width
                        // 只允许向左滑
                        if translation < 0 {
                            offset = translation
                            // 超过阈值时触发震动
                            if translation < deleteThreshold && !hasTriggeredHaptic {
                                hasTriggeredHaptic = true
                                let generator = UIImpactFeedbackGenerator(style: .heavy)
                                generator.impactOccurred()
                            }
                            if translation > deleteThreshold {
                                hasTriggeredHaptic = false
                            }
                        }
                    }
                    .onEnded { value in
                        if value.translation.width < deleteThreshold {
                            // 长滑直接删除
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset = -3000
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onDelete()
                            }
                        } else {
                            // 弹回
                            withAnimation(.spring(response: 0.3)) {
                                offset = 0
                            }
                        }
                        hasTriggeredHaptic = false
                    }
            )
    }
}

#Preview {
    FragmentListView()
        .environmentObject(FragmentStore.shared)
        .environmentObject(PortfolioStore.shared)
}
