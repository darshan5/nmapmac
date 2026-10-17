import Foundation

public enum NmapXMLError: Error, LocalizedError {
    case notNmapXML
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .notNmapXML: return "The file is not an Nmap XML output file."
        case .unreadable(let why): return "Could not read the scan: \(why)"
        }
    }
}

/// Reads and writes Nmap XML output, including Zenmap's extensions
/// (profile_name/scan_name attributes, interactive output, host comments).
public enum NmapXML {
    public static func parse(contentsOf url: URL) throws -> ScanResult {
        try parse(data: Data(contentsOf: url))
    }

    public static func parse(data: Data) throws -> ScanResult {
        let doc: XMLDocument
        do {
            // Nmap XML references an XSL stylesheet and sometimes is truncated
            // when a scan is cancelled; tidy lets us recover partial output.
            doc = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        } catch {
            do {
                doc = try XMLDocument(data: data, options: [.documentTidyXML, .nodeLoadExternalEntitiesNever])
            } catch {
                throw NmapXMLError.unreadable(error.localizedDescription)
            }
        }
        guard let root = doc.rootElement(), root.name == "nmaprun" else {
            throw NmapXMLError.notNmapXML
        }

        var scan = ScanResult()
        scan.rawXML = data
        scan.scanner = root.attr("scanner") ?? "nmap"
        scan.args = root.attr("args") ?? ""
        scan.version = root.attr("version") ?? ""
        scan.xmlOutputVersion = root.attr("xmloutputversion") ?? ""
        scan.startTime = root.attr("start").flatMap(date(fromEpoch:))
        scan.profileName = root.attr("profile_name") ?? ""
        scan.target = root.attr("zenmap_target") ?? ""

        for child in root.childElements {
            switch child.name {
            case "scaninfo":
                scan.scanInfo.append(ScanInfo(
                    type: child.attr("type") ?? "",
                    proto: child.attr("protocol") ?? "",
                    numServices: Int(child.attr("numservices") ?? "") ?? 0,
                    services: child.attr("services") ?? ""))
            case "verbose":
                scan.verbose = Int(child.attr("level") ?? "") ?? 0
            case "debugging":
                scan.debugging = Int(child.attr("level") ?? "") ?? 0
            case "host":
                scan.hosts.append(parseHost(child))
            case "prescript":
                scan.preScripts = child.elements(named: "script").map(parseScript)
            case "postscript":
                scan.postScripts = child.elements(named: "script").map(parseScript)
            case "runstats":
                if let finished = child.firstElement(named: "finished") {
                    scan.endTime = finished.attr("time").flatMap(date(fromEpoch:))
                    scan.elapsed = finished.attr("elapsed").flatMap(Double.init)
                    scan.summary = finished.attr("summary") ?? ""
                    scan.exitStatus = finished.attr("exit") ?? ""
                }
                if let hosts = child.firstElement(named: "hosts") {
                    scan.hostsUp = Int(hosts.attr("up") ?? "") ?? 0
                    scan.hostsDown = Int(hosts.attr("down") ?? "") ?? 0
                    scan.hostsTotal = Int(hosts.attr("total") ?? "") ?? 0
                }
            case "output":
                if child.attr("type") == "interactive" {
                    scan.normalOutput = child.stringValue ?? ""
                }
            default:
                break
            }
        }

        if scan.hostsTotal == 0 && !scan.hosts.isEmpty {
            scan.hostsUp = scan.hosts.filter(\.isUp).count
            scan.hostsDown = scan.hosts.count - scan.hostsUp
            scan.hostsTotal = scan.hosts.count
        }
        if scan.target.isEmpty {
            scan.target = NmapOptions(commandLine: scan.args).targets.joined(separator: " ")
        }
        return scan
    }

    // MARK: - Writing

    /// Produces XML for saving: Nmap's original document plus Zenmap metadata.
    public static func data(for scan: ScanResult) throws -> Data {
        guard let raw = scan.rawXML else {
            throw NmapXMLError.unreadable("this scan has no XML output to save")
        }
        let doc: XMLDocument
        do {
            doc = try XMLDocument(data: raw, options: [.nodeLoadExternalEntitiesNever])
        } catch {
            doc = try XMLDocument(data: raw, options: [.documentTidyXML, .nodeLoadExternalEntitiesNever])
        }
        guard let root = doc.rootElement() else { throw NmapXMLError.notNmapXML }

        root.setAttr("profile_name", scan.profileName)
        root.setAttr("zenmap_target", scan.target)
        root.setAttr("scan_name", scan.title)

        for old in root.elements(forName: "output") where old.attr("type") == "interactive" {
            old.detach()
        }
        if !scan.normalOutput.isEmpty {
            let output = XMLElement(name: "output", stringValue: scan.normalOutput)
            output.setAttr("type", "interactive")
            root.addChild(output)
        }

        // NmapHost elements are in the same order as scan.hosts.
        for (element, host) in zip(root.elements(forName: "host"), scan.hosts) {
            if host.comment.isEmpty {
                element.removeAttribute(forName: "comment")
            } else {
                element.setAttr("comment", host.comment)
            }
        }
        return doc.xmlData(options: [.nodePrettyPrint])
    }

    // MARK: - Element parsing

    static func parseHost(_ element: XMLElement) -> NmapHost {
        var host = NmapHost()
        host.comment = element.attr("comment") ?? ""
        host.startTime = element.attr("starttime").flatMap(date(fromEpoch:))
        host.endTime = element.attr("endtime").flatMap(date(fromEpoch:))

        for child in element.childElements {
            switch child.name {
            case "status":
                host.state = child.attr("state") ?? "unknown"
                host.reason = child.attr("reason") ?? ""
            case "address":
                host.addresses.append(Address(
                    addr: child.attr("addr") ?? "",
                    type: child.attr("addrtype") ?? "ipv4",
                    vendor: child.attr("vendor") ?? ""))
            case "hostnames":
                host.hostnames = child.elements(named: "hostname").map {
                    Hostname(name: $0.attr("name") ?? "", type: $0.attr("type") ?? "")
                }
            case "ports":
                for portChild in child.childElements {
                    if portChild.name == "port" {
                        host.ports.append(parsePort(portChild))
                    } else if portChild.name == "extraports" {
                        host.extraPorts.append(ExtraPorts(
                            state: portChild.attr("state") ?? "",
                            count: Int(portChild.attr("count") ?? "") ?? 0))
                    }
                }
            case "os":
                for osChild in child.childElements {
                    if osChild.name == "portused" {
                        host.portsUsed.append(PortUsed(
                            state: osChild.attr("state") ?? "",
                            proto: osChild.attr("proto") ?? "",
                            portID: Int(osChild.attr("portid") ?? "") ?? 0))
                    } else if osChild.name == "osmatch" {
                        host.osMatches.append(parseOSMatch(osChild))
                    }
                }
            case "uptime":
                host.uptimeSeconds = Int(child.attr("seconds") ?? "")
                host.lastBoot = child.attr("lastboot") ?? ""
            case "distance":
                host.distance = Int(child.attr("value") ?? "")
            case "tcpsequence":
                host.tcpSequence = SequenceInfo(
                    index: child.attr("index") ?? "",
                    difficulty: child.attr("difficulty") ?? "",
                    values: child.attr("values") ?? "")
            case "ipidsequence":
                host.ipIDSequence = SequenceInfo(
                    classDescription: child.attr("class") ?? "",
                    values: child.attr("values") ?? "")
            case "tcptssequence":
                host.tcpTSSequence = SequenceInfo(
                    classDescription: child.attr("class") ?? "",
                    values: child.attr("values") ?? "")
            case "trace":
                var trace = Trace(port: child.attr("port") ?? "", proto: child.attr("proto") ?? "")
                trace.hops = child.elements(named: "hop").map {
                    TraceHop(
                        ttl: Int($0.attr("ttl") ?? "") ?? 0,
                        ipAddress: $0.attr("ipaddr") ?? "",
                        rtt: $0.attr("rtt") ?? "--",
                        host: $0.attr("host") ?? "")
                }
                host.trace = trace
            case "hostscript":
                host.hostScripts = child.elements(named: "script").map(parseScript)
            default:
                break
            }
        }
        return host
    }

    static func parsePort(_ element: XMLElement) -> NmapPort {
        var port = NmapPort(
            proto: element.attr("protocol") ?? "tcp",
            portID: Int(element.attr("portid") ?? "") ?? 0,
            state: "unknown")
        if let state = element.firstElement(named: "state") {
            port.state = state.attr("state") ?? "unknown"
            port.reason = state.attr("reason") ?? ""
            port.reasonTTL = state.attr("reason_ttl") ?? ""
        }
        if let svc = element.firstElement(named: "service") {
            port.service.name = svc.attr("name") ?? ""
            port.service.product = svc.attr("product") ?? ""
            port.service.version = svc.attr("version") ?? ""
            port.service.extraInfo = svc.attr("extrainfo") ?? ""
            port.service.osType = svc.attr("ostype") ?? ""
            port.service.method = svc.attr("method") ?? ""
            port.service.conf = svc.attr("conf") ?? ""
            port.service.tunnel = svc.attr("tunnel") ?? ""
        }
        port.scripts = element.elements(named: "script").map(parseScript)
        return port
    }

    static func parseOSMatch(_ element: XMLElement) -> OSMatch {
        var match = OSMatch(
            name: element.attr("name") ?? "",
            accuracy: Int(element.attr("accuracy") ?? "") ?? 0,
            line: element.attr("line") ?? "")
        match.classes = element.elements(named: "osclass").map {
            OSClass(
                type: $0.attr("type") ?? "",
                vendor: $0.attr("vendor") ?? "",
                family: $0.attr("osfamily") ?? "",
                generation: $0.attr("osgen") ?? "",
                accuracy: Int($0.attr("accuracy") ?? "") ?? 0,
                cpe: $0.elements(named: "cpe").compactMap(\.stringValue))
        }
        return match
    }

    static func parseScript(_ element: XMLElement) -> ScriptResult {
        ScriptResult(id: element.attr("id") ?? "", output: element.attr("output") ?? "")
    }

    static func date(fromEpoch string: String) -> Date? {
        TimeInterval(string).map { Date(timeIntervalSince1970: $0) }
    }
}

// MARK: - XMLElement conveniences

extension XMLElement {
    func attr(_ name: String) -> String? {
        attribute(forName: name)?.stringValue
    }

    func setAttr(_ name: String, _ value: String) {
        if let existing = attribute(forName: name) {
            existing.stringValue = value
        } else if let node = XMLNode.attribute(withName: name, stringValue: value) as? XMLNode {
            addAttribute(node)
        }
    }

    var childElements: [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }
    }

    func elements(named name: String) -> [XMLElement] {
        elements(forName: name)
    }

    func firstElement(named name: String) -> XMLElement? {
        elements(forName: name).first
    }
}
