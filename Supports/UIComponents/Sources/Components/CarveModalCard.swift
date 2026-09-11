import SwiftUI

/// I1·I2 안내 카드. 제목과 버튼은 고정하고 작은 창에서는 본문만 스크롤한다.
public struct CarveModalCard<Content: View, Actions: View>: View {
    private let title: String
    private let subtitle: String?
    private let content: Content
    private let actions: Actions

    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.actions = actions()
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                CarveColor.scrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CarveColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(CarveColor.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 28)

                    CarveDivider()
                    ScrollView {
                        content
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 24)
                    }
                    CarveDivider()
                    HStack(spacing: 0) {
                        actions
                    }
                    .frame(height: 90)
                    .buttonStyle(.plain)
                    .font(.system(size: 15))
                }
                .frame(
                    width: min(500, max(0, geometry.size.width - 32)),
                    height: min(620, max(0, geometry.size.height - 32))
                )
                .carveSurface(.panel, in: RoundedRectangle(cornerRadius: CarveRadius.panel))
                .clipShape(RoundedRectangle(cornerRadius: CarveRadius.panel))
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
