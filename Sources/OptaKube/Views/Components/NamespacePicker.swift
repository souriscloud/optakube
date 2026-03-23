import SwiftUI

struct NamespacePicker: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        Menu {
            Button("All Namespaces") {
                viewModel.selectedNamespace = nil
                Task { await viewModel.refresh() }
            }

            Divider()

            ForEach(allNamespaces, id: \.self) { ns in
                Button {
                    viewModel.selectedNamespace = ns
                    Task { await viewModel.refresh() }
                } label: {
                    HStack {
                        Text(ns)
                        if viewModel.selectedNamespace == ns {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tray.2")
                Text(viewModel.selectedNamespace ?? "All Namespaces")
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var allNamespaces: [String] {
        var namespaces: Set<String> = []
        for (_, nsList) in viewModel.availableNamespaces {
            nsList.forEach { namespaces.insert($0) }
        }
        return namespaces.sorted()
    }
}
