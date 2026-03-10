import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
	appId: 'com.retold.remoteios',
	appName: 'Retold Remote',
	webDir: 'web-app',
	ios: {
		allowsLinkPreview: false,
	},
	server: {
		// Allow navigation to any retold-remote server on the local network
		allowNavigation: ['*'],
	},
};

export default config;
