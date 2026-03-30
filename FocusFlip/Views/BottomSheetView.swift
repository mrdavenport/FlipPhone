import SwiftUI

struct BottomSheetView<Content: View>: View {
    @Binding var isExpanded: Bool
    let collapsedHeight: CGFloat
    let expandedHeightRatio: CGFloat
    let screenHeight: CGFloat
    let content: Content
    
    @State private var dragOffset: CGFloat = 0
    @State private var currentHeight: CGFloat
    @State private var isDragging: Bool = false
    
    init(
        isExpanded: Binding<Bool>,
        screenHeight: CGFloat,
        collapsedHeight: CGFloat = 213, // Matches design spec
        expandedHeightRatio: CGFloat = 0.8,
        @ViewBuilder content: () -> Content
    ) {
        self._isExpanded = isExpanded
        self.screenHeight = screenHeight
        self.collapsedHeight = collapsedHeight
        self.expandedHeightRatio = expandedHeightRatio
        self.content = content()
        // Start with collapsed height
        _currentHeight = State(initialValue: collapsedHeight)
    }
    
    var body: some View {
        let maxHeight = screenHeight * expandedHeightRatio
        let minHeight = collapsedHeight
        let sheetHeight = min(max(currentHeight + dragOffset, minHeight), maxHeight)
        let contentHeight = max(0, sheetHeight - 30) // 30px for handle
        
        VStack(spacing: 0) {
            // Drag handle area
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
            .frame(height: 30)
            
            // Content area with draggable top section
            ZStack(alignment: .top) {
                content
                    .frame(height: contentHeight, alignment: .top)
                    .clipped()
                
                // Invisible draggable overlay for header section only (not tabs)
                // This covers approximately the first 120px where the header is
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 120) // Approximate height of header only (date + total time)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDragging {
                                        isDragging = true
                                        
                                        let translation = value.translation.height
                                        let isInitialTouch = abs(translation) < 10
                                        
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            if isInitialTouch {
                                                if !isExpanded {
                                                    currentHeight = maxHeight
                                                    dragOffset = 0
                                                    isExpanded = true
                                                } else {
                                                    currentHeight = minHeight
                                                    dragOffset = 0
                                                    isExpanded = false
                                                }
                                            } else {
                                                let isDraggingUp = translation < 0
                                                
                                                if isDraggingUp && !isExpanded {
                                                    currentHeight = maxHeight
                                                    dragOffset = 0
                                                    isExpanded = true
                                                } else if !isDraggingUp && isExpanded {
                                                    currentHeight = minHeight
                                                    dragOffset = 0
                                                    isExpanded = false
                                                }
                                            }
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    dragOffset = 0
                                }
                        )
                    
                    Spacer()
                }
            }
        }
        // Also keep drag handle gesture for the handle bar itself
        .background(
            VStack {
                Spacer()
                    .frame(height: 0)
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            
                            let translation = value.translation.height
                            let isInitialTouch = abs(translation) < 10
                            
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if isInitialTouch {
                                    if !isExpanded {
                                        currentHeight = maxHeight
                                        dragOffset = 0
                                        isExpanded = true
                                    } else {
                                        currentHeight = minHeight
                                        dragOffset = 0
                                        isExpanded = false
                                    }
                                } else {
                                    let isDraggingUp = translation < 0
                                    
                                    if isDraggingUp && !isExpanded {
                                        currentHeight = maxHeight
                                        dragOffset = 0
                                        isExpanded = true
                                    } else if !isDraggingUp && isExpanded {
                                        currentHeight = minHeight
                                        dragOffset = 0
                                        isExpanded = false
                                    }
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragOffset = 0
                    }
            )
        )
        .frame(height: sheetHeight)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onChange(of: isExpanded) { oldValue, newValue in
            if !isDragging {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    currentHeight = newValue ? maxHeight : minHeight
                    dragOffset = 0
                }
            }
        }
        .onAppear {
            let maxHeight = screenHeight * expandedHeightRatio
            currentHeight = isExpanded ? maxHeight : collapsedHeight
        }
    }
}

