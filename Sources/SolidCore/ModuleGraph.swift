import Foundation

/// Local SPM-style modules discovered from the directory layout, plus the
/// import graph between them (built from real `import` statements).
/// Shared by `init` (ConfigGenerator) and the visibility rule.
public struct ModuleGraph {
    public struct Module: Equatable {
        public let name: String
        /// Module directory relative to the root, with a trailing slash
        /// (e.g. `Sources/Foo/` or `Packages/Foo/Sources/`).
        public let pathPrefix: String
        public init(name: String, pathPrefix: String) {
            self.name = name
            self.pathPrefix = pathPrefix
        }
    }

    public let root: String
    public let modules: [Module]
    /// module name → local module names it imports (never contains self).
    public let imports: [String: Set<String>]

    /// Modules that no other local module imports.
    public var leafModules: [Module] {
        let importedSomewhere = imports.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        return modules.filter { !importedSomewhere.contains($0.name) }
    }

    /// Discover modules under `root` (layouts: `--packages-dir`, then
    /// `Packages/<M>/Sources`, then `Sources/<M>`) and build the import graph.
    public static func build(root: String, packagesDir: String? = nil) -> ModuleGraph {
        let modules = discoverModules(root: root, packagesDir: packagesDir)
        let names = Set(modules.map(\.name))
        var graph: [String: Set<String>] = [:]
        for module in modules {
            let dir = (root as NSString).appendingPathComponent(module.pathPrefix)
            var imported: Set<String> = []
            for file in swiftFiles(under: dir, excluding: ["/Tests/"]) {
                guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
                for imp in ImportCollector.imports(in: source)
                where names.contains(imp.module) && imp.module != module.name {
                    imported.insert(imp.module)
                }
            }
            graph[module.name] = imported
        }
        return ModuleGraph(root: root, modules: modules, imports: graph)
    }

    // MARK: - §5.1 Module discovery

    private static func discoverModules(root: String, packagesDir: String?) -> [Module] {
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
}
