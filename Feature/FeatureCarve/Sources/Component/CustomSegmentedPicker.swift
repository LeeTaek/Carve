//
//  CustomSegmentedPicker.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

public struct SegmentedPicker<SelectionValue, Content>: View where SelectionValue: Hashable, Content: View {
    @Namespace private var pickerTransition
    @Binding public var selection: SelectionValue
    public var items: [SelectionValue]
    private var selectionColor: Color = .teal
    private var content: (SelectionValue) -> Content
    
    public init(
        selection: Binding<SelectionValue>,
        items: [SelectionValue],
        selectionColor: Color = .teal,
        @ViewBuilder content: @escaping (SelectionValue) -> Content
    ) {
        self._selection = selection
        self.items = items
        self.selectionColor = selectionColor
        self.content = content
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.flexible())], spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        let selected = (selection == item)
                        ZStack {
                            Capsule()
                                .foregroundStyle(selected ? selectionColor : .clear)
                                .animationEffect(isSelected: selected, id: "picker", in: pickerTransition)
                            content(item)
                                .id(item)
                                .pickerTextStyle(isSelected: selected)
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selection = item
                            }
                        }
                        .onChange(of: selection) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(selection)
                            }
                        }
                    }
                    .onAppear {
                        if let first = items.first {
                            selection = first
                        }
                    }
                }
                .padding(.horizontal)
                .fixedSize(horizontal: false, vertical: true)
            }
            
        }
    }
}

public struct PickerStyle: ViewModifier {
    var isSelected = true
    var selectionColor: Color = .teal
    
    public func body(content: Content) -> some View {
        content
            .foregroundColor(isSelected ? .white : .black)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .lineLimit(1)
            .clipShape(.capsule)
    }
}
