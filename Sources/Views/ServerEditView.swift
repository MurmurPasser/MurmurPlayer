import SwiftUI

struct ServerEditView: View {
    let original: SMBServer?
    let onSave: (SMBServer) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var discovery = SMBDiscovery()

    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var domain: String
    @State private var defaultShare: String

    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?
    @State private var availableShares: [String] = []
    @State private var passwordNotSaved = false

    init(server: SMBServer?, onSave: @escaping (SMBServer) -> Void) {
        original = server
        self.onSave = onSave
        _name = State(initialValue: server?.name ?? "")
        _host = State(initialValue: server?.host ?? "")
        _port = State(initialValue: server?.port.map { String($0) } ?? "")
        _username = State(initialValue: server?.username ?? "")
        _password = State(initialValue: server.map { ServerStore.shared.password(for: $0) } ?? "")
        _domain = State(initialValue: server?.domain ?? "")
        _defaultShare = State(initialValue: server?.defaultShare ?? "")
    }

    private var draft: SMBServer {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return SMBServer(id: original?.id ?? UUID(),
                         name: name.trimmingCharacters(in: .whitespaces).isEmpty ? cleanHost : name.trimmingCharacters(in: .whitespaces),
                         host: cleanHost,
                         port: Int(port.trimmingCharacters(in: .whitespaces)),
                         username: username.trimmingCharacters(in: .whitespaces),
                         domain: domain.trimmingCharacters(in: .whitespaces),
                         defaultShare: defaultShare.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")))
    }

    private var canSave: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if original == nil {
                    discoverySection
                }

                Section {
                    TextField("Nombre (ej. NAS de la sala)", text: $name)
                    TextField("IP o nombre (ej. 192.168.1.20)", text: $host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Puerto (vacío = 445)", text: $port)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Servidor")
                }

                Section {
                    TextField("Usuario (vacío = invitado)", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Contraseña", text: $password)
                    TextField("Dominio / grupo de trabajo (opcional)", text: $domain)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Cuenta")
                } footer: {
                    Text("La contraseña se guarda en el llavero del iPad.")
                }

                Section {
                    if availableShares.isEmpty {
                        TextField("Recurso compartido (opcional, ej. video)", text: $defaultShare)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Picker("Abrir directamente", selection: $defaultShare) {
                            Text("Mostrar todos").tag("")
                            ForEach(availableShares, id: \.self) { share in
                                Text(share).tag(share)
                            }
                        }
                    }
                } header: {
                    Text("Carpeta inicial")
                } footer: {
                    Text("Si lo dejas vacío verás la lista de recursos compartidos del servidor.")
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Probar conexión")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(!canSave || testing)

                    if let testResult {
                        Label(testResult.text, systemImage: testResult.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(testResult.ok ? Color.green : Color.orange)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle(original == nil ? "Nuevo servidor" : "Editar servidor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let server = draft
                        let saved = ServerStore.shared.upsert(server, password: password)
                        onSave(server)
                        if saved { dismiss() } else { passwordNotSaved = true }
                    }
                    .disabled(!canSave)
                }
            }
            .alert("No se pudo guardar la contraseña", isPresented: $passwordNotSaved) {
                Button("OK") { dismiss() }
            } message: {
                Text("El servidor quedó guardado, pero el llavero del dispositivo rechazó la contraseña. Vuelve a escribirla más tarde en «Editar servidor».")
            }
            .onAppear { if original == nil { discovery.start() } }
            .onDisappear { discovery.stop() }
        }
    }

    private var discoverySection: some View {
        Section {
            if discovery.found.isEmpty {
                HStack(spacing: 10) {
                    if discovery.isSearching { ProgressView() }
                    Text(discovery.isSearching ? "Buscando servidores SMB en tu red…" : "No se encontraron servidores. Escribe la IP abajo.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(discovery.found) { item in
                Button {
                    host = item.host
                    if name.isEmpty { name = item.name }
                } label: {
                    HStack {
                        Image(systemName: "externaldrive.connected.to.line.below")
                        VStack(alignment: .leading) {
                            Text(item.name).foregroundStyle(.primary)
                            Text(item.host).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if host == item.host {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        } header: {
            Text("En tu red")
        }
    }

    private func testConnection() async {
        testing = true
        testResult = nil
        defer { testing = false }
        do {
            let session = try SMBSession(server: draft, password: password)
            let shares = try await session.listShares()
            availableShares = shares
            if !defaultShare.isEmpty, !shares.contains(defaultShare) {
                defaultShare = ""
            }
            testResult = (true, shares.isEmpty ? "Conectado, pero sin recursos visibles." : "Conectado: \(shares.count) recurso(s) compartido(s).")
        } catch {
            testResult = (false, SMBError.friendly(error))
        }
    }
}
