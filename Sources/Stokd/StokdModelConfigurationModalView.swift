import SwiftUI

struct StokdModelConfigurationModalView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: StokdModelConfigurationViewModel
    private let directory: String

    init(
        initialTab: StokdModelConfigurationTab,
        directory: String,
        loader: any StokdModelConfigurationLoading = StokdModelConfigurationCLILoader()
    ) {
        self.directory = directory
        _model = StateObject(wrappedValue: StokdModelConfigurationViewModel(initialTab: initialTab, loader: loader))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 860, idealWidth: 920, minHeight: 600, idealHeight: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: directory) {
            model.refresh(directory: directory)
        }
        .accessibilityIdentifier("stokdModelConfiguration.modal")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.selectedTab == .defaults ? "server.rack" : "gearshape.2")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "stokdModelConfiguration.title", defaultValue: "Stokd Model Configuration"))
                    .font(.system(size: 14, weight: .semibold))
                Text(directory)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "stokdModelConfiguration.close", defaultValue: "Close"))
            .accessibilityLabel(String(localized: "stokdModelConfiguration.close", defaultValue: "Close"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker(
                String(localized: "stokdModelConfiguration.tab.label", defaultValue: "Configuration tab"),
                selection: $model.selectedTab
            ) {
                ForEach(StokdModelConfigurationTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .labelsHidden()

            Picker(
                String(localized: "stokdModelConfiguration.scope.label", defaultValue: "Write scope"),
                selection: $model.scope
            ) {
                ForEach(StokdModelConfigurationWriteScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .labelsHidden()

            Spacer(minLength: 0)

            if let success = model.successMessage {
                Text(success)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Button {
                model.refresh(directory: directory)
            } label: {
                Label(
                    String(localized: "stokdModelConfiguration.refresh", defaultValue: "Refresh"),
                    systemImage: "arrow.clockwise"
                )
            }
            .controlSize(.small)
            .disabled(model.state == .loading || model.isApplying)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .populated:
            populatedContent
        case .idle, .loading, .empty:
            StokdModelConfigurationStateView(
                title: model.state.message,
                symbol: stateSymbol,
                showsProgress: model.state == .loading,
                actionTitle: model.state == .empty
                    ? String(localized: "stokdModelConfiguration.refresh", defaultValue: "Refresh")
                    : nil,
                action: model.state == .empty
                    ? { model.refresh(directory: directory) }
                    : nil
            )
        case let .failure(message):
            StokdModelConfigurationStateView(
                title: message,
                symbol: "exclamationmark.triangle",
                showsProgress: false,
                actionTitle: String(localized: "stokdModelConfiguration.retry", defaultValue: "Retry"),
                action: { model.refresh(directory: directory) }
            )
        }
    }

    private var populatedContent: some View {
        HStack(spacing: 0) {
            catalogPanel
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
            Divider()
            editorPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var catalogPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "stokdModelConfiguration.catalog.title", defaultValue: "Catalog"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(model.filteredCatalog.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            TextField(
                String(localized: "stokdModelConfiguration.catalog.search", defaultValue: "Search models"),
                text: $model.searchText
            )
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.filteredCatalog) { catalogModel in
                        StokdModelCatalogRow(
                            model: catalogModel,
                            onAddDefaults: { model.addModelToDefaults(catalogModel.id) },
                            onAddWorkload: { model.addModelToSelectedWorkload(catalogModel.id) }
                        )
                    }
                    if model.filteredCatalog.isEmpty {
                        Text(String(localized: "stokdModelConfiguration.catalog.empty", defaultValue: "No matching models"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(24)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var editorPanel: some View {
        switch model.selectedTab {
        case .defaults:
            defaultsEditor
        case .workloads:
            workloadEditor
        }
    }

    private var defaultsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            StokdModelConfigurationSectionHeader(
                title: String(localized: "stokdModelConfiguration.defaults.title", defaultValue: "Default Model Order"),
                subtitle: String(localized: "stokdModelConfiguration.defaults.subtitle", defaultValue: "One model id per line. Saved as models.defaults.")
            )

            StokdModelChipList(
                models: model.defaults,
                removeAction: model.removeDefault
            )

            TextEditor(text: $model.defaultsText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                .accessibilityLabel(String(localized: "stokdModelConfiguration.defaults.title", defaultValue: "Default Model Order"))

            HStack {
                Spacer(minLength: 0)
                Button {
                    model.applyDefaults(directory: directory)
                } label: {
                    Label(
                        String(localized: "stokdModelConfiguration.apply", defaultValue: "Apply"),
                        systemImage: "checkmark"
                    )
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.isApplying)
            }
        }
        .padding(16)
    }

    private var workloadEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            StokdModelConfigurationSectionHeader(
                title: String(localized: "stokdModelConfiguration.workloads.title", defaultValue: "Workload Routing"),
                subtitle: String(localized: "stokdModelConfiguration.workloads.subtitle", defaultValue: "Override one workload chain at models.workloads.<name>.")
            )

            if !model.workloads.isEmpty {
                Picker(
                    String(localized: "stokdModelConfiguration.workloads.selector", defaultValue: "Workload"),
                    selection: Binding(
                        get: { model.selectedWorkloadSlug },
                        set: { model.selectWorkload(slug: $0) }
                    )
                ) {
                    ForEach(model.workloads) { workload in
                        Text(workload.slug).tag(workload.slug)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 260, alignment: .leading)
            }

            TextField(
                String(localized: "stokdModelConfiguration.workloads.key", defaultValue: "Workload key"),
                text: Binding(
                    get: { model.selectedWorkloadSlug },
                    set: { model.selectedWorkloadSlug = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)

            StokdModelChipList(
                models: model.selectedWorkloadModels,
                removeAction: model.removeWorkloadModel
            )

            TextEditor(text: $model.selectedWorkloadModelsText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                .accessibilityLabel(String(localized: "stokdModelConfiguration.workloads.title", defaultValue: "Workload Routing"))

            HStack {
                Spacer(minLength: 0)
                Button {
                    model.applySelectedWorkload(directory: directory)
                } label: {
                    Label(
                        String(localized: "stokdModelConfiguration.apply", defaultValue: "Apply"),
                        systemImage: "checkmark"
                    )
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.isApplying || model.selectedWorkloadSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
    }

    private var stateSymbol: String {
        switch model.state {
        case .loading:
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case .empty:
            return "tray"
        case .idle, .populated, .failure:
            return "server.rack"
        }
    }
}

private struct StokdModelCatalogRow: View {
    let model: StokdModelConfigurationCatalogModel
    let onAddDefaults: () -> Void
    let onAddWorkload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(model.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let capability = model.capability {
                    Text("\(Int(capability.rounded()))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.teal, in: RoundedRectangle(cornerRadius: 4))
                }
            }

            HStack(spacing: 5) {
                Text(model.providerConfigID.isEmpty ? model.provider : model.providerConfigID)
                if let pricing = model.pricing,
                   let input = pricing.inputPer1M {
                    Text("$\(input, specifier: "%.2f")/M")
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Button {
                    onAddDefaults()
                } label: {
                    Label(
                        String(localized: "stokdModelConfiguration.add.defaults", defaultValue: "Defaults"),
                        systemImage: "plus"
                    )
                }
                .controlSize(.mini)

                Button {
                    onAddWorkload()
                } label: {
                    Label(
                        String(localized: "stokdModelConfiguration.add.workload", defaultValue: "Workload"),
                        systemImage: "plus"
                    )
                }
                .controlSize(.mini)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.12)))
        .accessibilityIdentifier("stokdModelConfiguration.catalog.\(model.id)")
    }
}

private struct StokdModelChipList: View {
    let models: [String]
    let removeAction: (String) -> Void

    var body: some View {
        if models.isEmpty {
            Text(String(localized: "stokdModelConfiguration.selection.placeholder", defaultValue: "No models selected"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(models, id: \.self) { id in
                        HStack(spacing: 4) {
                            Text(id)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                            Button {
                                removeAction(id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "stokdModelConfiguration.remove", defaultValue: "Remove"))
                            .accessibilityLabel(String(localized: "stokdModelConfiguration.remove", defaultValue: "Remove"))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(height: 28)
        }
    }
}

private struct StokdModelConfigurationSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StokdModelConfigurationStateView: View {
    let title: String
    let symbol: String
    let showsProgress: Bool
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
