import Foundation
import Testing
@testable import NMapMacCore

private func fixture(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures"))
}

@Suite struct NmapXMLTests {
    @Test func parsesRealOutput() throws {
        let scan = try NmapXML.parse(contentsOf: fixture("localhost"))
        #expect(scan.version == "7.94")
        #expect(scan.hosts.count == 1)
        #expect(scan.hosts[0].primaryAddress == "127.0.0.1")
        #expect(scan.target == "127.0.0.1")
    }

    @Test func parsesHostDetails() throws {
        let scan = try NmapXML.parse(contentsOf: fixture("os-trace"))
        #expect(scan.hostsUp == 2 && scan.hostsDown == 1)
        let web = scan.hosts[0]
        #expect(web.hostname == "web.example.com")
        #expect(web.mac?.vendor == "Acme")
        #expect(web.openPortCount == 2)
        #expect(web.closedPortCount == 997)
        #expect(web.filteredPortCount == 1)
        #expect(web.bestOSMatch?.name == "Linux 5.0 - 5.14")
        #expect(web.osIconName == "linux")
        #expect(web.trace?.hops.count == 3)
        #expect(web.ports[1].scripts.first?.id == "http-title")
        #expect(web.ports[0].service.versionString == "OpenSSH 8.9p1 (Ubuntu Linux; protocol 2.0)")
        #expect(scan.hosts[1].osIconName == "win")
    }

    @Test func roundTripsZenmapMetadata() throws {
        var scan = try NmapXML.parse(contentsOf: fixture("os-trace"))
        scan.profileName = "Intense scan"
        scan.normalOutput = "Starting Nmap <&>"
        scan.hosts[0].comment = "web server"
        let reparsed = try NmapXML.parse(data: NmapXML.data(for: scan))
        #expect(reparsed.profileName == "Intense scan")
        #expect(reparsed.normalOutput == "Starting Nmap <&>")
        #expect(reparsed.hosts[0].comment == "web server")
        #expect(reparsed.hosts.count == 3)
    }

    @Test func rejectsOtherXML() {
        #expect(throws: NmapXMLError.self) {
            try NmapXML.parse(data: Data("<foo/>".utf8))
        }
    }
}

@Suite struct NmapOptionsTests {
    @Test func parsesProfileCommand() {
        let opts = NmapOptions(commandLine: #"nmap -sS -sU -T4 -A -v -PE -PS80,443 -PA3389 --source-port 53 --script "default or (discovery and safe)" scanme.nmap.org"#)
        #expect(opts.has("-sS") && opts.has("-sU") && opts.has("-A"))
        #expect(opts.argument(for: "-T") == "4")
        #expect(opts.argument(for: "-PS") == "80,443")
        #expect(opts.argument(for: "--source-port") == "53")
        #expect(opts.argument(for: "--script") == "default or (discovery and safe)")
        #expect(opts.targets == ["scanme.nmap.org"])
    }

    @Test func roundTrips() {
        let line = #"nmap -T4 -p 1-1000 -PS22,80 --script "safe and default" -v2 10.0.0.0/24"#
        let opts = NmapOptions(commandLine: line)
        #expect(NmapOptions(commandLine: opts.commandLine) == opts)
        #expect(opts.commandLine == line)
    }

    @Test func handlesShortForms() {
        let opts = NmapOptions(commandLine: "nmap -sSV -vvv -p22 -sI zombie -oX - --max-retries=3 host")
        #expect(opts.has("-sS") && opts.has("-sV"))
        #expect(opts.argument(for: "-v") == "3")
        #expect(opts.argument(for: "-p") == "22")
        #expect(opts.argument(for: "-sI") == "zombie")
        #expect(opts.argument(for: "-oX") == "-")
        #expect(opts.argument(for: "--max-retries") == "3")
        #expect(opts.targets == ["host"])
    }

    @Test func editing() {
        var opts = NmapOptions(commandLine: "nmap -T4 -F host")
        opts.set("-T", argument: "2")
        opts.remove("-F")
        opts.set("-O")
        #expect(opts.commandLine == "nmap -T2 -O host")
    }
}

@Suite struct SavedCommandTests {
    private func tempStore() -> (SavedCommandStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).usp")
        return (SavedCommandStore(fileURL: url), url)
    }

    @Test func loadsBuiltInScanTypes() {
        let builtIn = SavedCommandStore.bundledCommands
        #expect(builtIn.count == 10)
        #expect(builtIn.first { $0.name == "Quick scan" }?.command == "nmap -T4 -F")
    }

    @Test func serializationRoundTrips() {
        let commands = [SavedCommand(name: "A", command: "nmap -F", description: "line 1\nline 2")]
        #expect(SavedCommandFile.parse(SavedCommandFile.serialize(commands)) == commands)
    }

    @Test func savesWithoutTargetsAndOverwrites() throws {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try store.save(name: "Web", command: "nmap -p 80,443 -sV 192.168.1.0/24")
        #expect(store.command(named: "Web")?.command == "nmap -p 80,443 -sV")
        try store.save(name: "Web", command: "nmap -p 80,443,8080 -sV")
        let reloaded = SavedCommandStore(fileURL: url)
        #expect(reloaded.custom.count == 1)
        #expect(reloaded.command(named: "Web")?.command == "nmap -p 80,443,8080 -sV")
        // Only the user's commands are written to disk.
        #expect(try String(contentsOf: url, encoding: .utf8).contains("Quick scan") == false)
        try reloaded.delete(named: "Web")
        #expect(SavedCommandStore(fileURL: url).custom.isEmpty)
    }

    @Test func protectsBuiltIns() {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: SavedCommandError.self) { try store.save(name: "Quick scan", command: "nmap") }
        #expect(throws: SavedCommandError.self) { try store.save(name: "  ", command: "nmap") }
    }
}

@Suite struct SearchQueryTests {
    let scan: ScanResult

    init() throws {
        scan = try NmapXML.parse(contentsOf: fixture("os-trace"))
    }

    @Test func filtersHosts() {
        let web = scan.hosts[0]
        let win = scan.hosts[1]
        #expect(SearchQuery("nginx").matches(web))
        #expect(!SearchQuery("nginx").matches(win))
        #expect(SearchQuery("os:windows").matches(win))
        #expect(SearchQuery("open:22,80").matches(web))
        #expect(!SearchQuery("open:443").matches(web))
        #expect(SearchQuery("filtered:443").matches(web))
        #expect(SearchQuery("service:ssh target:10.0.0").matches(web))
        #expect(SearchQuery("inroute:192.168.1.1").matches(win))
    }

    @Test func searchesScans() {
        var named = scan
        named.profileName = "Intense scan"
        #expect(SearchQuery("profile:intense").matches(named))
        #expect(SearchQuery("option:-A").matches(named))
        #expect(SearchQuery("date:2023-11-14~1").matches(named))
        #expect(!SearchQuery("before:2023-01-01").matches(named))
        #expect(!SearchQuery("os:solaris").matches(named))
    }
}

@Suite struct InventoryAndDiffTests {
    @Test func mergesNewestHost() throws {
        let old = try NmapXML.parse(contentsOf: fixture("os-trace"))
        var new = old
        new.startTime = old.startTime!.addingTimeInterval(10)
        new.hosts[0].ports.removeAll()
        let inventory = Inventory(scans: [old, new])
        #expect(inventory.hosts.count == 2)
        #expect(inventory.hosts.first { $0.primaryAddress == "10.0.0.2" }?.ports.isEmpty == true)
    }

    @Test func diffReportsPortChanges() throws {
        let a = try NmapXML.parse(contentsOf: fixture("os-trace"))
        var b = a
        b.hosts[0].ports[0].state = "closed"
        let lines = ScanDiff.compare(a, b)
        #expect(lines.contains { $0.kind == .removed && $0.text.hasPrefix("-22/tcp") && $0.text.contains("open") })
        #expect(lines.contains { $0.kind == .added && $0.text.hasPrefix("+22/tcp") && $0.text.contains("closed") })
        #expect(ScanDiff.compare(a, a).contains { $0.text.contains("No differences") })
    }

    @Test func topologyFollowsTraceroute() throws {
        let scan = try NmapXML.parse(contentsOf: fixture("os-trace"))
        let topo = Topology(hosts: scan.hosts.filter(\.isUp))
        #expect(topo.nodes["192.168.1.1"]?.parentID == Topology.rootID)
        #expect(topo.nodes["10.0.0.2"]?.parentID == "10.0.0.1")
        #expect(topo.nodes["10.0.0.3"]?.parentID == "192.168.1.1")
        #expect(topo.maxRing == 3)
    }
}

@Suite struct TargetRangeTests {
    @Test func buildsSpecsFromRanges() {
        func spec(_ a: String, _ b: String) -> String {
            TargetRange.spec(from: IPv4(a)!, to: IPv4(b)!)
        }
        #expect(spec("192.168.1.1", "192.168.1.254") == "192.168.1.1-254")
        #expect(spec("192.168.1.50", "192.168.1.10") == "192.168.1.10-50")
        #expect(spec("10.0.0.5", "10.0.0.5") == "10.0.0.5")
        #expect(spec("10.0.0.0", "10.0.2.255") == "10.0.0.0/23 10.0.2.0/24")
        #expect(spec("192.168.0.250", "192.168.1.3") == "192.168.0.250/31 192.168.0.252/30 192.168.1.0/30")
    }

    @Test func summarizesTargets() {
        let s = TargetRange.summarize("192.168.1.0/24 10.0.0.1-10 scanme.nmap.org")
        #expect(s.addressCount == 266)
        #expect(s.first == "10.0.0.1" && s.last == "192.168.1.255")
        #expect(s.hostNames == ["scanme.nmap.org"])
        #expect(TargetRange.summarize("192.168.*.1").addressCount == 256)
        #expect(TargetRange.summarize("10.0.0.1,3,5").addressCount == 3)
        #expect(TargetRange.summarize("300.1.1.1").invalid == ["300.1.1.1"])
    }

    @Test func computesNetworks() {
        let net = TargetRange.network(address: IPv4("192.168.1.37")!, netmask: IPv4("255.255.255.0")!)
        #expect(net.cidr == "192.168.1.0/24")
        #expect(net.end.description == "192.168.1.255")
    }

    @Test func findsLocalNetworksWithoutCrashing() {
        for network in LocalNetwork.current() {
            #expect(network.addressCount >= 1)
        }
    }
}
