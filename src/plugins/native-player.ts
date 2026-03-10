import { registerPlugin } from '@capacitor/core';

export interface NativePlayerPlugin
{
	/**
	 * Play a video file using the native MPVKit player.
	 * Presents a full-screen player with hardware-accelerated decoding.
	 */
	playVideo(options: { url: string; title: string }): Promise<void>;

	/**
	 * Play an audio file using native AVPlayer with background audio support.
	 * Registers with MPNowPlayingInfoCenter for lock screen controls.
	 */
	playAudio(options: { url: string; title: string }): Promise<void>;

	/**
	 * Stop any currently playing media.
	 */
	stop(): Promise<void>;

	/**
	 * Get the current playback status.
	 */
	getStatus(): Promise<{
		playing: boolean;
		url: string;
		title: string;
		position: number;
		duration: number;
	}>;
}

const NativePlayer = registerPlugin<NativePlayerPlugin>('NativePlayer');

export default NativePlayer;

// Also expose on window for the bridge script
if (typeof window !== 'undefined')
{
	(window as any).RetoldNativePlayer = NativePlayer;
}
