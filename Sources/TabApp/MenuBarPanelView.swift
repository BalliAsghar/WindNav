import AppKit
import SwiftUI
import TabCore

struct MenuBarPanelView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var hoveredRowID: String?

    private let panelWidth: CGFloat = 292
    private let rowMinHeight: CGFloat = 36
    private let rowHorizontalPadding: CGFloat = 10
    private let rowVerticalPadding: CGFloat = 2
    private let rowCornerRadius: CGFloat = 6
    private let chipSize: CGFloat = 24
    private let chipSymbolSize: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            sectionLabel("Features")
            featureToggleRow(
                id: "feature.cmdtab",
                title: MenuBarViewModel.FeatureToggle.cmdTabOverride.rowTitle,
                systemImage: "command.square",
                isOn: Binding(
                    get: { viewModel.isFeatureEnabled(.cmdTabOverride) },
                    set: { viewModel.setFeature(.cmdTabOverride, enabled: $0) }
                )
            )
            featureDivider
            featureToggleRow(
                id: "feature.directional",
                title: MenuBarViewModel.FeatureToggle.directionalNavigation.rowTitle,
                systemImage: "arrow.left.and.right.circle",
                isOn: Binding(
                    get: { viewModel.isFeatureEnabled(.directionalNavigation) },
                    set: { viewModel.setFeature(.directionalNavigation, enabled: $0) }
                )
            )
            featureDivider
            featureToggleRow(
                id: "feature.thumbnails",
                title: MenuBarViewModel.FeatureToggle.thumbnails.rowTitle,
                systemImage: "photo.on.rectangle",
                isOn: Binding(
                    get: { viewModel.isFeatureEnabled(.thumbnails) },
                    set: { viewModel.setFeature(.thumbnails, enabled: $0) }
                )
            )

            Divider()
                .padding(.top, 4)

            sectionLabel("Permissions")
            permissionRow(
                id: "permission.accessibility",
                permission: .accessibility,
                systemImage: "figure.roll"
            )
            featureDivider
            permissionRow(
                id: "permission.input",
                permission: .inputMonitoring,
                systemImage: "keyboard"
            )
            featureDivider
            permissionRow(
                id: "permission.screen",
                permission: .screenRecording,
                systemImage: "record.circle"
            )

            Divider()
                .padding(.top, 4)

            sectionLabel("Preferences")
            featureToggleRow(
                id: "preference.launch-at-login",
                title: "Launch at Login",
                systemImage: "arrow.right.circle",
                isOn: Binding(
                    get: { viewModel.isLaunchAtLoginEnabled() },
                    set: { viewModel.setLaunchAtLoginEnabled($0) }
                )
            )

            Divider()
                .padding(.top, 4)

            quitRow
        }
        .frame(width: panelWidth)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("WindNav")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 5) {
                    Image(systemName: viewModel.summaryText == "Status: Ready" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(viewModel.summaryText == "Status: Ready" ? Color.green : Color.orange)
                    Text(viewModel.summaryText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private var featureDivider: some View {
        Divider()
            .padding(.horizontal, rowHorizontalPadding)
    }

    private func featureToggleRow(
        id: String,
        title: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        rowContainer(id: id) {
            HStack(spacing: 10) {
                iconChip(systemImage: systemImage)
                Text(title)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .fixedSize()
            }
        }
    }

    private func permissionRow(
        id: String,
        permission: PermissionKind,
        systemImage: String
    ) -> some View {
        Button {
            viewModel.handlePermissionRowClick(permission)
        } label: {
            rowContainer(id: id) {
                HStack(spacing: 10) {
                    iconChip(systemImage: systemImage)
                    Text(menuBarPermissionTitle(permission))
                        .font(.system(size: 13))
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Text(viewModel.statusLabel(for: permission))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Image(systemName: viewModel.permissionStatus(for: permission) == .granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(viewModel.permissionStatus(for: permission) == .granted ? Color.green : Color.orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .pointingHandCursorOnHover()
    }

    private var quitRow: some View {
        Button(action: { NSApplication.shared.terminate(nil) }) {
            HStack(spacing: 6) {
                Image(systemName: "power")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Quit WindNav")
                    .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func rowContainer<Content: View>(id: String, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: rowMinHeight, alignment: .leading)
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
            .contentShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .fill(hoveredRowID == id ? Color.primary.opacity(0.08) : .clear)
            )
            .padding(.horizontal, 6)
            .onHover { hovering in
                hoveredRowID = hovering ? id : (hoveredRowID == id ? nil : hoveredRowID)
            }
    }

    private func iconChip(systemImage: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.16))
            Image(systemName: systemImage)
                .font(.system(size: chipSymbolSize, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: chipSize, height: chipSize)
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.15) : .clear)
            )
    }
}

private struct PointingHandCursorOnHover: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    guard !isHovering else { return }
                    NSCursor.pointingHand.push()
                    isHovering = true
                } else {
                    guard isHovering else { return }
                    NSCursor.pop()
                    isHovering = false
                }
            }
            .onDisappear {
                guard isHovering else { return }
                NSCursor.pop()
                isHovering = false
            }
    }
}

private extension View {
    func pointingHandCursorOnHover() -> some View {
        modifier(PointingHandCursorOnHover())
    }
}
