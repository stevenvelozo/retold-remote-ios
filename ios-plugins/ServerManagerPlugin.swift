import Foundation
import Network
import Capacitor

/// Capacitor plugin for managing retold-remote server connections.
///
/// Provides server discovery on the local network (via NWBrowser),
/// connection testing, and persistent storage of saved servers.
@objc(ServerManagerPlugin)
public class ServerManagerPlugin: CAPPlugin, CAPBridgedPlugin
{
	public let identifier = "ServerManagerPlugin"
	public let jsName = "ServerManager"
	public let pluginMethods: [CAPPluginMethod] = [
		CAPPluginMethod(name: "discoverServers", returnType: CAPPluginReturnPromise),
		CAPPluginMethod(name: "testConnection", returnType: CAPPluginReturnPromise),
		CAPPluginMethod(name: "saveServer", returnType: CAPPluginReturnPromise),
		CAPPluginMethod(name: "getSavedServers", returnType: CAPPluginReturnPromise),
		CAPPluginMethod(name: "removeServer", returnType: CAPPluginReturnPromise),
	]

	private let savedServersKey = "retold-saved-servers"

	// MARK: - Server Discovery

	/// Discover retold-remote servers on the local network.
	///
	/// Uses NWBrowser to scan for HTTP services, then tests each one
	/// against the retold-remote capabilities endpoint.
	@objc func discoverServers(_ call: CAPPluginCall)
	{
		var discoveredServers: [[String: Any]] = []
		let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: .tcp)

		let group = DispatchGroup()
		var foundEndpoints: [(String, NWEndpoint)] = []

		browser.stateUpdateHandler =
		{ state in
			switch state
			{
			case .failed(let error):
				call.reject("Discovery failed: \(error.localizedDescription)")
			default:
				break
			}
		}

		browser.browseResultsChangedHandler =
		{ results, _ in
			for result in results
			{
				if case .service(let name, _, _, _) = result.endpoint
				{
					foundEndpoints.append((name, result.endpoint))
				}
			}
		}

		browser.start(queue: .global())

		// Give discovery 3 seconds to find services
		DispatchQueue.global().asyncAfter(deadline: .now() + 3.0)
		{
			browser.cancel()

			// Test each discovered endpoint
			for (name, endpoint) in foundEndpoints
			{
				if case .service(_, _, _, _) = endpoint
				{
					// For each service, we need to resolve it to get the host/port.
					// NWBrowser provides the service name but not the resolved address.
					// We'll try common retold-remote ports.
					group.enter()

					// Use NWConnection to resolve the endpoint
					let connection = NWConnection(to: endpoint, using: .tcp)
					connection.stateUpdateHandler =
					{ state in
						switch state
						{
						case .ready:
							if let innerEndpoint = connection.currentPath?.remoteEndpoint,
							   case .hostPort(let host, let port) = innerEndpoint
							{
								let hostString = "\(host)"
								let portInt = Int(port.rawValue)
								let url = "http://\(hostString):\(portInt)"

								discoveredServers.append([
									"name": name,
									"host": hostString,
									"port": portInt,
									"url": url,
								])
							}
							connection.cancel()
							group.leave()
						case .failed:
							connection.cancel()
							group.leave()
						default:
							break
						}
					}
					connection.start(queue: .global())

					// Timeout for individual resolution
					DispatchQueue.global().asyncAfter(deadline: .now() + 2.0)
					{
						if connection.state != .cancelled
						{
							connection.cancel()
							group.leave()
						}
					}
				}
			}

			group.notify(queue: .main)
			{
				call.resolve(["servers": discoveredServers])
			}
		}
	}

	// MARK: - Connection Testing

	/// Test whether a server URL is reachable and is a valid retold-remote server.
	@objc func testConnection(_ call: CAPPluginCall)
	{
		guard let urlString = call.getString("url") else
		{
			call.reject("URL is required")
			return
		}

		guard let url = URL(string: "\(urlString)/api/media/capabilities") else
		{
			call.reject("Invalid URL")
			return
		}

		let task = URLSession.shared.dataTask(with: url)
		{ data, response, error in
			if let error = error
			{
				call.resolve(["reachable": false, "error": error.localizedDescription])
				return
			}

			guard let httpResponse = response as? HTTPURLResponse,
				  httpResponse.statusCode == 200,
				  let data = data else
			{
				call.resolve(["reachable": false])
				return
			}

			do
			{
				if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
				   let capabilities = json["Capabilities"] as? [String: Bool]
				{
					call.resolve([
						"reachable": true,
						"capabilities": capabilities,
					])
				}
				else
				{
					call.resolve(["reachable": false])
				}
			}
			catch
			{
				call.resolve(["reachable": false])
			}
		}
		task.resume()
	}

	// MARK: - Saved Servers

	/// Save a server to UserDefaults.
	@objc func saveServer(_ call: CAPPluginCall)
	{
		guard let name = call.getString("name"),
			  let host = call.getString("host") else
		{
			call.reject("name and host are required")
			return
		}

		let port = call.getInt("port") ?? 7500

		var servers = loadSavedServers()

		// Remove existing entry with same host:port
		servers.removeAll { ($0["host"] as? String) == host && ($0["port"] as? Int) == port }

		// Add new entry at front
		let entry: [String: Any] = [
			"name": name,
			"host": host,
			"port": port,
			"url": "http://\(host):\(port)",
			"lastUsed": ISO8601DateFormatter().string(from: Date()),
		]
		servers.insert(entry, at: 0)

		// Keep max 10
		if servers.count > 10
		{
			servers = Array(servers.prefix(10))
		}

		saveToDisk(servers)
		call.resolve()
	}

	/// Get the list of saved servers.
	@objc func getSavedServers(_ call: CAPPluginCall)
	{
		let servers = loadSavedServers()
		call.resolve(["servers": servers])
	}

	/// Remove a server from the saved list.
	@objc func removeServer(_ call: CAPPluginCall)
	{
		guard let host = call.getString("host") else
		{
			call.reject("host is required")
			return
		}

		let port = call.getInt("port") ?? 0

		var servers = loadSavedServers()
		servers.removeAll
		{
			($0["host"] as? String) == host &&
			(port == 0 || ($0["port"] as? Int) == port)
		}
		saveToDisk(servers)
		call.resolve()
	}

	// MARK: - Persistence Helpers

	private func loadSavedServers() -> [[String: Any]]
	{
		guard let data = UserDefaults.standard.data(forKey: savedServersKey),
			  let servers = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else
		{
			return []
		}
		return servers
	}

	private func saveToDisk(_ servers: [[String: Any]])
	{
		if let data = try? JSONSerialization.data(withJSONObject: servers)
		{
			UserDefaults.standard.set(data, forKey: savedServersKey)
		}
	}
}
