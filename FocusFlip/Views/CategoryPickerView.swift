import SwiftUI
import SwiftData
import UIKit

struct CategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCategory: SessionCategory
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(SessionCategory.allCases) { category in
                        categoryButton(category: category)
                    }
                }
                .padding(24)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
            }
        }
    }
    
    private func categoryButton(category: SessionCategory) -> some View {
        Button {
            selectedCategory = category
            AnalyticsService.shared.logCategorySelected(category.displayName)
            #if DEBUG
            let uiColor = UIColor(category.color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            print("QA [CategoryPickerView] selectedCategory id=\(category.id) displayName=\(category.displayName) colorRGBA=(\(r),\(g),\(b),\(a))")
            #endif
            dismiss()
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(category.color)
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: category.icon)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Text(category.displayName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selectedCategory == category ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selectedCategory == category ? category.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

