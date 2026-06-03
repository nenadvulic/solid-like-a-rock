import Foundation

/// How `init` should derive the deny lists.
public enum InitMode {
    /// Freeze the status quo: deny every local module a module does NOT import today.
    case freeze
    /// Heuristic: rank modules by depth and deny only "outward" dependencies.
    case layered
}

public enum ConfigGeneratorError: Error, CustomStringConvertible {
    case noModules(String)
    case invalidGeneratedYAML(String)

    public var description: String {
        switch self {
        case .noModules(let root):  return "no local modules found under \(root)"
        case .invalidGeneratedYAML(let why): return "generated YAML failed to validate: \(why)"
        }
    }
}

/// Generates a starter `.solid.yml` by analysing a project's real inter-module
/// import graph — deterministic, no LLM. Emits one layer per local module; the
/// user regroups/renames into real layers afterwards.
public struct ConfigGenerator {
    private struct Module { let name: String; let pathPrefix: String }

    private let root: String
    private let packagesDir: String?

    public init(root: String, packagesDir: String? = nil) {
        self.root = root
        self.packagesDir = packagesDir
    }

    public func generate(mode: InitMode) throws -> String {
        let modules = discoverModules()
        guard !modules.isEmpty else { throw ConfigGeneratorError.noModules(root) }

        let names = Set(modules.map(\.name))
        let graph = buildGraph(modules: modules, localModules: names)

        let denies: [String: [String]]
        var rankComment = ""
        switch mode {
        case .freeze:
            denies = freezeDenies(modules: modules, localModules: names, graph: graph)
        case .layered:
            let (d, comment) = layeredDenies(modules: modules, localModules: names, graph: graph)
            denies = d
            rankComment = comment
        }

        let yaml = renderYAML(modules: modules, denies: denies, mode: mode, rankComment: rankComment)
        try validate(yaml)
        return yaml
    }

    // MARK: - §5.1 Module discovery

    private func discoverModules() -> [Module] {
        let fm = FileManager.default
        func hasSwift(_ dir: String) -> Bool {
            !swiftFiles(under: dir, excluding: ["/Tests/"]).isEmpty
        }
        func modulesIn(container: String, relativePrefix: (String) -> String) -> [Module] {
            guard let entries = try? fm.contentsOfDirectory(atPath: container) else { return [] }
            return entries.sorted().compactMap { name in
                let dir = (container as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }
                guard hasSwift(dir) else { return nil }
                return Module(name: name, pathPrefix: relativePrefix(name))
            }
        }

        // Explicit --packages-dir, or auto-detect Packages/<M>/Sources, else Sources/<M>.
        if let pkgDir = packagesDir {
            let container = (root as NSString).appendingPathComponent(pkgDir)
            return modulesIn(container: container) { "\(pkgDir)/\($0)/" }
        }
        let packages = (root as NSString).appendingPathComponent("Packages")
        if fm.fileExists(atPath: packages) {
            // multi-package: Packages/<M>/Sources
            let multi = (try? fm.contentsOfDirectory(atPath: packages))?.sorted().compactMap { name -> Module? in
                let srcDir = packages + "/" + name + "/Sources"
                guard fm.fileExists(atPath: srcDir), hasSwift(srcDir) else { return nil }
                return Module(name: name, pathPrefix: "Packages/\(name)/Sources/")
            } ?? []
            if !multi.isEmpty { return multi }
        }
        let sources = (root as NSString).appendingPathComponent("Sources")
        if fm.fileExists(atPath: sources) {
            return modulesIn(container: sources) { "Sources/\($0)/" }
        }
        return []
    }

    // MARK: - §5.2 Import graph

    private func buildGraph(modules: [Module], localModules: Set<String>) -> [String: Set<String>] {
        var graph: [String: Set<String>] = [:]
        for module in modules {
            let dir = (root as NSString).appendingPathComponent(module.pathPrefix)
            var imported: Set<String> = []
            for file in swiftFiles(under: dir, excluding: ["/Tests/"]) {
                guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
                for imp in ImportCollector.imports(in: source) where localModules.contains(imp.module) && imp.module != module.name {
                    imported.insert(imp.module)
                }
            }
            graph[module.name] = imported
        }
        return graph
    }

    // MARK: - §5.3 Freeze

    private func freezeDenies(modules: [Module], localModules: Set<String>,
                              graph: [String: Set<String>]) -> [String: [String]] {
        var denies: [String: [String]] = [:]
        for module in modules {
            let imported = graph[module.name] ?? []
            denies[module.name] = localModules.subtracting(imported).subtracting([module.name]).sorted()
        }
        return denies
    }

    // MARK: - §5.4 Layered (rank by longest path on the condensed DAG)

    private func layeredDenies(modules: [Module], localModules: Set<String>,
                               graph: [String: Set<String>]) -> ([String: [String]], String) {
        let sccs = stronglyConnectedComponents(nodes: localModules, edges: graph)
        // Map each module to its component id.
        var comp: [String: Int] = [:]
        for (i, scc) in sccs.enumerated() { for n in scc { comp[n] = i } }

        // Condensed edges between components.
        var condEdges: [Int: Set<Int>] = [:]
        for (from, tos) in graph {
            for to in tos where comp[from] != comp[to] {
                condEdges[comp[from]!, default: []].insert(comp[to]!)
            }
        }
        // rank(c) = longest outgoing (import) chain: 0 if it imports nothing local,
        // else 1 + max(rank of imported components). Process sinks first by walking
        // the topological order in reverse, so successors are already computed.
        var rankOfComp = [Int: Int](uniqueKeysWithValues: (0..<sccs.count).map { ($0, 0) })
        for cid in topologicalOrder(nodeCount: sccs.count, edges: condEdges).reversed() {
            let successors = condEdges[cid] ?? []
            if !successors.isEmpty {
                rankOfComp[cid] = 1 + successors.map { rankOfComp[$0]! }.max()!
            }
        }
        var rank: [String: Int] = [:]
        for module in modules { rank[module.name] = rankOfComp[comp[module.name]!]! }

        var denies: [String: [String]] = [:]
        for module in modules {
            let r = rank[module.name]!
            denies[module.name] = localModules.filter { rank[$0]! > r }.sorted()
        }

        // Header comment listing modules grouped by rank.
        let byRank = Dictionary(grouping: modules.map(\.name), by: { rank[$0]! })
        var lines = byRank.keys.sorted().map { r in
            "#   rank \(r): " + byRank[r]!.sorted().joined(separator: ", ")
        }
        let cyclic = sccs.filter { $0.count > 1 }
        if !cyclic.isEmpty {
            lines.append("# WARNING: import cycles detected (treated as one rank): "
                         + cyclic.map { $0.sorted().joined(separator: "↔") }.joined(separator: "; "))
        }
        return (denies, lines.joined(separator: "\n"))
    }

    /// Tarjan's strongly-connected components.
    private func stronglyConnectedComponents(nodes: Set<String>,
                                             edges: [String: Set<String>]) -> [[String]] {
        var index = 0
        var stack: [String] = []
        var onStack: Set<String> = []
        var indices: [String: Int] = [:]
        var low: [String: Int] = [:]
        var result: [[String]] = []

        func strongConnect(_ v: String) {
            indices[v] = index; low[v] = index; index += 1
            stack.append(v); onStack.insert(v)
            for w in (edges[v] ?? []).sorted() {
                if indices[w] == nil {
                    strongConnect(w)
                    low[v] = min(low[v]!, low[w]!)
                } else if onStack.contains(w) {
                    low[v] = min(low[v]!, indices[w]!)
                }
            }
            if low[v] == indices[v] {
                var scc: [String] = []
                while true {
                    let w = stack.removeLast(); onStack.remove(w); scc.append(w)
                    if w == v { break }
                }
                result.append(scc)
            }
        }
        for v in nodes.sorted() where indices[v] == nil { strongConnect(v) }
        return result
    }

    private func topologicalOrder(nodeCount: Int, edges: [Int: Set<Int>]) -> [Int] {
        var indegree = [Int](repeating: 0, count: nodeCount)
        for (_, tos) in edges { for to in tos { indegree[to] += 1 } }
        var queue = (0..<nodeCount).filter { indegree[$0] == 0 }.sorted()
        var order: [Int] = []
        while !queue.isEmpty {
            let n = queue.removeFirst(); order.append(n)
            for next in (edges[n] ?? []).sorted() {
                indegree[next] -= 1
                if indegree[next] == 0 { queue.append(next); queue.sort() }
            }
        }
        return order
    }

    // MARK: - §6 YAML rendering + validation

    private func renderYAML(modules: [Module], denies: [String: [String]],
                            mode: InitMode, rankComment: String) -> String {
        let modeName = mode == .freeze ? "freeze" : "layered"
        var out = """
        # .solid.yml — generated by `solid-like-a-rock init` (mode: \(modeName))
        # Modules detected: \(modules.count). Review and regroup into business layers if needed.

        """
        if !rankComment.isEmpty { out += rankComment + "\n" }
        out += """

        alwaysAllow:
          - Foundation

        layers:

        """
        for module in modules.sorted(by: { $0.name < $1.name }) {
            out += "  - name: \(module.name)\n"
            out += "    paths:\n"
            out += "      - \(module.pathPrefix)\n"
            if let deny = denies[module.name], !deny.isEmpty {
                out += "    deny:\n"
                for d in deny { out += "      - \(d)\n" }
            }
        }
        return out
    }

    private func validate(_ yaml: String) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("solid-init-validate-\(UUID().uuidString).yml")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try yaml.write(to: url, atomically: true, encoding: .utf8)
            let config = try Configuration.load(from: url.path)
            try config.validate()
        } catch {
            throw ConfigGeneratorError.invalidGeneratedYAML("\(error)")
        }
    }
}
