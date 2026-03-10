import Foundation
import AVFoundation
import MediaPlayer
import Capacitor

/// Capacitor plugin for native video and audio playback.
///
/// Video playback uses MPVKit (libmpv) for full codec support with
/// hardware-accelerated decoding via VideoToolbox.
/// Audio playback uses AVPlayer with background audio and lock screen controls.
///
/// To use MPVKit, add it via Swift Package Manager in Xcode:
///   File > Add Package Dependencies > https://github.com/mpvkit/MPVKit
@objc(NativePlayerPlugin)
public class NativePlayerPlugin: CAPPlugin, CAPBridgedPlugin
{
	public let identifier = "NativePlayerPlugin"
	public let jsName = "NativePlayer"
	public let pluginMethods: [CAPPluginMethod] = [
		CAPPluginMethod(name: "playVideo", returnType: CAPPluginReturnPromise),
		CAPPluginMethod(name: "playAudio", returnType: CAPPluginReturnPromise),
		CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
		CAPPluginMethod(name: "getStatus", returnType: CAPPluginReturnPromise),
	]

	private var audioPlayer: AVPlayer?
	private var mpvPlayerVC: MPVPlayerViewController?
	private var isPlaying: Bool = false
	private var currentURL: String = ""
	private var currentTitle: String = ""

	// MARK: - Video Playback

	/// Play a video file using MPVKit for full codec support.
	///
	/// Uses MPVPlayerViewController which embeds libmpv with VideoToolbox
	/// hardware decoding. Supports MKV, HEVC 10-bit, and other formats
	/// that AVPlayer cannot handle.
	@objc func playVideo(_ call: CAPPluginCall)
	{
		guard let urlString = call.getString("url") else
		{
			call.reject("URL is required")
			return
		}

		let title = call.getString("title") ?? "Video"

		guard let url = URL(string: urlString) else
		{
			call.reject("Invalid URL")
			return
		}

		DispatchQueue.main.async
		{
			self.currentURL = urlString
			self.currentTitle = title
			self.isPlaying = true

			let playerVC = MPVPlayerViewController(url: url, title: title)
			playerVC.onDismiss =
			{ [weak self] in
				self?.mpvPlayerVC = nil
				self?.isPlaying = false
			}
			self.mpvPlayerVC = playerVC

			if let viewController = self.bridge?.viewController
			{
				viewController.present(playerVC, animated: true)
			}

			self.updateNowPlaying(title: title, duration: 0)

			call.resolve()
		}
	}

	// MARK: - Audio Playback

	/// Play an audio file using AVPlayer with background audio support.
	@objc func playAudio(_ call: CAPPluginCall)
	{
		guard let urlString = call.getString("url") else
		{
			call.reject("URL is required")
			return
		}

		let title = call.getString("title") ?? "Audio"

		guard let url = URL(string: urlString) else
		{
			call.reject("Invalid URL")
			return
		}

		// Configure audio session for background playback
		do
		{
			let session = AVAudioSession.sharedInstance()
			try session.setCategory(.playback, mode: .default)
			try session.setActive(true)
		}
		catch
		{
			call.reject("Failed to configure audio session: \(error.localizedDescription)")
			return
		}

		// Stop any existing playback
		audioPlayer?.pause()

		currentURL = urlString
		currentTitle = title
		isPlaying = true

		// Create player and start playback
		let playerItem = AVPlayerItem(url: url)
		audioPlayer = AVPlayer(playerItem: playerItem)
		audioPlayer?.play()

		// Set up lock screen controls
		setupRemoteCommandCenter()
		updateNowPlaying(title: title, duration: 0)

		// Observe when playback finishes
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(audioDidFinishPlaying),
			name: .AVPlayerItemDidPlayToEndTime,
			object: playerItem
		)

		call.resolve()
	}

	// MARK: - Stop

	/// Stop any currently playing media.
	@objc func stop(_ call: CAPPluginCall)
	{
		// Dismiss MPV player if active
		if let mpvVC = mpvPlayerVC
		{
			mpvVC.dismiss(animated: true)
			mpvPlayerVC = nil
		}

		audioPlayer?.pause()
		audioPlayer = nil
		isPlaying = false
		currentURL = ""
		currentTitle = ""

		MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

		call.resolve()
	}

	// MARK: - Status

	/// Get the current playback status.
	@objc func getStatus(_ call: CAPPluginCall)
	{
		var position: Double = 0
		var duration: Double = 0

		if let player = audioPlayer
		{
			position = player.currentTime().seconds
			if let item = player.currentItem
			{
				duration = item.duration.seconds
				if duration.isNaN { duration = 0 }
			}
		}

		call.resolve([
			"playing": isPlaying,
			"url": currentURL,
			"title": currentTitle,
			"position": position,
			"duration": duration,
		])
	}

	// MARK: - Now Playing & Remote Commands

	private func updateNowPlaying(title: String, duration: Double)
	{
		var nowPlayingInfo: [String: Any] = [
			MPMediaItemPropertyTitle: title,
			MPNowPlayingInfoPropertyPlaybackRate: 1.0,
		]

		if duration > 0
		{
			nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
		}

		if let player = audioPlayer
		{
			nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
		}

		MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
	}

	private func setupRemoteCommandCenter()
	{
		let commandCenter = MPRemoteCommandCenter.shared()

		commandCenter.playCommand.isEnabled = true
		commandCenter.playCommand.addTarget
		{ [weak self] _ in
			self?.audioPlayer?.play()
			self?.isPlaying = true
			return .success
		}

		commandCenter.pauseCommand.isEnabled = true
		commandCenter.pauseCommand.addTarget
		{ [weak self] _ in
			self?.audioPlayer?.pause()
			self?.isPlaying = false
			return .success
		}

		commandCenter.togglePlayPauseCommand.isEnabled = true
		commandCenter.togglePlayPauseCommand.addTarget
		{ [weak self] _ in
			guard let self = self else { return .commandFailed }
			if self.isPlaying
			{
				self.audioPlayer?.pause()
				self.isPlaying = false
			}
			else
			{
				self.audioPlayer?.play()
				self.isPlaying = true
			}
			return .success
		}

		commandCenter.changePlaybackPositionCommand.isEnabled = true
		commandCenter.changePlaybackPositionCommand.addTarget
		{ [weak self] event in
			guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else
			{
				return .commandFailed
			}
			let time = CMTime(seconds: positionEvent.positionTime, preferredTimescale: 600)
			self?.audioPlayer?.seek(to: time)
			return .success
		}
	}

	@objc private func audioDidFinishPlaying()
	{
		isPlaying = false
		MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
	}
}
