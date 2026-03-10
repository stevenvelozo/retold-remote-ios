import { registerPlugin } from '@capacitor/core';

export interface ServerManagerPlugin
{
	/**
	 * Discover retold-remote servers on the local network via Bonjour/mDNS.
	 * Scans for HTTP services and returns those that respond to the
	 * retold-remote capabilities endpoint.
	 */
	discoverServers(): Promise<{
		servers: Array<{
			name: string;
			host: string;
			port: number;
			url: string;
		}>;
	}>;

	/**
	 * Test whether a server URL is reachable and is a valid retold-remote server.
	 */
	testConnection(options: { url: string }): Promise<{
		reachable: boolean;
		capabilities?: Record<string, boolean>;
	}>;

	/**
	 * Save a server to the persistent server list.
	 */
	saveServer(options: { name: string; host: string; port: number }): Promise<void>;

	/**
	 * Get the list of saved servers.
	 */
	getSavedServers(): Promise<{
		servers: Array<{
			name: string;
			host: string;
			port: number;
			url: string;
			lastUsed: string;
		}>;
	}>;

	/**
	 * Remove a server from the saved list.
	 */
	removeServer(options: { host: string; port: number }): Promise<void>;
}

const ServerManager = registerPlugin<ServerManagerPlugin>('ServerManager');

export default ServerManager;
