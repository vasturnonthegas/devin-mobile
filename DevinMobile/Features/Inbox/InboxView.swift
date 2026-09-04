import SwiftUI
import DevinKit

struct InboxView: View {
    @Bindable var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var scope: InboxScopeModel
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var tab: InboxTab = .active
    @State private var showNewSession = false
    @State private var showSettings = false
    @State private var members: MemberLookup

    init(store: SessionStore) {
        _store = Bindable(store)
        _scope = State(initialValue: InboxScopeModel(client: store.client, orgID: store.orgID))
        _members = State(initialValue: MemberLookup(client: store.client, orgID: store.orgID))
    }

    var body: some View {
        NavigationStack(path: $path) {
            scopedContent
                .navigationTitle("Sessions")
                .navigationDestination(for: Session.self) { session in
                    SessionDetailView(store: store, sessionID: session.id)
                }
                .searchable(text: $query, prompt: "Title, tag, or ID")
                .refreshable { await store.refresh() }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showSettings = true } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        Picker("Scope", selection: $scope.scope) {
                            ForEach(InboxScope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                        .disabled(!scope.isMineAvailable)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNewSession = true } label: {
                            Label("New session", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showNewSession) {
                    NewSessionView(store: store) { created in
                        path.append(created)
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
        }
        .task { store.startPolling() }
        .task { await scope.resolveIdentity() }
        .task { await members.load() }
        .onDisappear { store.stopPolling() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: store.startPolling()
            case .background, .inactive: store.stopPolling()
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private var scopedContent: some View {
        Group {
            switch tab {
            case .active: content
            case .archived: ArchivedSessionsView(store: store, query: query)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Tab", selection: $tab) {
                ForEach(InboxTab.allCases) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    /// Owner chips only add information when rows can belong to other people.
    private var showsOwners: Bool { scope.effectiveScope == .everyone }

    @ViewBuilder
    private var content: some View {
        let groups = scope.filter(store.filtered(by: query))
        if (store.sessions.isEmpty && store.isLoading) || (scope.isIdentityPending && scope.scope == .mine) {
            ProgressView("Loading sessions…")
        } else if let error = store.error, store.sessions.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load sessions", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Retry") { Task { await store.refresh() } }
            }
        } else if groups.isEmpty {
            let mode = scope.effectiveScope
            ContentUnavailableView(
                query.isEmpty ? mode.emptyTitle : "No matches",
                systemImage: query.isEmpty ? mode.systemImage : "magnifyingglass",
                description: Text(query.isEmpty ? mode.emptyDescription : "Try a different search.")
            )
        } else {
            let prefetchIDs = Set(groups.flatMap(\.sessions).suffix(Self.prefetchWindow).map(\.id))
            List {
                ForEach(groups, id: \.bucket) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            NavigationLink(value: session) {
                                SessionRow(session: session, owner: showsOwners ? members.owner(of: session) : nil)
                            }
                            .onAppear {
                                if prefetchIDs.contains(session.id) {
                                    Task { await store.loadMore() }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Archive", systemImage: "archivebox") {
                                    Task { try? await store.archive(session) }
                                }
                                .tint(.indigo)
                            }
                        }
                    } header: {
                        HStack {
                            Text(group.bucket.title)
                            if group.bucket == .needsYou {
                                Text("\(group.sessions.count)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                if store.hasMorePages {
                    Section {
                        InboxLoadMoreRow(store: store)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay(alignment: .bottom) {
                if let error = store.error {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .padding(8)
                        .background(.red.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                        .padding()
                        .transition(.move(edge: .bottom))
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: Session
    var owner: OrgMember? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.displayTitle)
                    .font(.body.weight(session.needsAttention ? .semibold : .regular))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(session.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                StatusBadge(session: session)
                if !session.pullRequests.isEmpty {
                    Label("\(session.pullRequests.count)", systemImage: "arrow.triangle.pull")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if session.acusConsumed > 0 {
                    Text("\(session.acusConsumed, format: .number.precision(.fractionLength(0...1))) ACU")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let mode = session.devinMode, mode != .normal {
                    Text(mode.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
            }
            if !session.tags.isEmpty || owner != nil {
                HStack(spacing: 8) {
                    if !session.tags.isEmpty {
                        Text(session.tags.map { "#\($0)" }.joined(separator: "  "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let owner {
                        MemberChip(member: owner)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
