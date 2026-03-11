import UIKit
import MPVKit

/// Full-screen video player using MPVKit (libmpv) for hardware-accelerated playback.
///
/// Supports MKV, HEVC 10-bit, and other formats that AVPlayer cannot handle.
/// Uses VideoToolbox for hardware decoding when available.
///
/// Features:
/// - Tap to show/hide overlay controls
/// - Play/pause, seek bar, close button
/// - Swipe left/right to seek ±10s
/// - Auto-hide overlay after 3 seconds of inactivity
class MPVPlayerViewController: UIViewController
{
	// MARK: - Properties

	private let videoURL: URL
	private let videoTitle: String
	var onDismiss: (() -> Void)?

	private var mpv: OpaquePointer?
	private var mpvGL: OpaquePointer?
	private var glView: MPVOGLView?

	private var isOverlayVisible = true
	private var overlayHideTimer: Timer?
	private var isSeeking = false
	private var duration: Double = 0
	private var position: Double = 0
	private var isPaused = false

	// MARK: - UI Elements

	private let overlayView = UIView()
	private let closeButton = UIButton(type: .system)
	private let titleLabel = UILabel()
	private let playPauseButton = UIButton(type: .system)
	private let seekBar = UISlider()
	private let timeLabel = UILabel()
	private let bottomBar = UIView()

	// MARK: - Initialization

	init(url: URL, title: String)
	{
		self.videoURL = url
		self.videoTitle = title
		super.init(nibName: nil, bundle: nil)
		self.modalPresentationStyle = .fullScreen
	}

	required init?(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	// MARK: - Lifecycle

	override func viewDidLoad()
	{
		super.viewDidLoad()
		view.backgroundColor = .black

		setupGLView()
		setupOverlay()
		setupGestures()
		initializeMPV()
	}

	override func viewDidAppear(_ animated: Bool)
	{
		super.viewDidAppear(animated)
		loadAndPlay()
		scheduleOverlayHide()
	}

	override func viewWillDisappear(_ animated: Bool)
	{
		super.viewWillDisappear(animated)
		overlayHideTimer?.invalidate()
		destroyMPV()
	}

	override var prefersStatusBarHidden: Bool { true }
	override var prefersHomeIndicatorAutoHidden: Bool { true }
	override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

	// MARK: - MPV Setup

	private func setupGLView()
	{
		let glView = MPVOGLView(frame: view.bounds)
		glView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		view.addSubview(glView)
		self.glView = glView
	}

	private func initializeMPV()
	{
		mpv = mpv_create()
		guard let mpv = mpv else { return }

		// Hardware decoding via VideoToolbox
		mpv_set_option_string(mpv, "hwdec", "videotoolbox")
		mpv_set_option_string(mpv, "vo", "gpu")
		mpv_set_option_string(mpv, "gpu-api", "opengl")
		mpv_set_option_string(mpv, "keep-open", "yes")

		// Performance tuning
		mpv_set_option_string(mpv, "cache", "yes")
		mpv_set_option_string(mpv, "demuxer-max-bytes", "50MiB")
		mpv_set_option_string(mpv, "demuxer-max-back-bytes", "25MiB")

		mpv_initialize(mpv)

		// Set up OpenGL rendering callback
		if let glView = glView
		{
			var params: [mpv_render_param] = glView.mpvGLParams()
			mpv_render_context_create(&mpvGL, mpv, &params)
			glView.mpvGL = mpvGL
		}

		// Observe properties for UI updates
		mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
		mpv_observe_property(mpv, 1, "duration", MPV_FORMAT_DOUBLE)
		mpv_observe_property(mpv, 2, "pause", MPV_FORMAT_FLAG)
		mpv_observe_property(mpv, 3, "eof-reached", MPV_FORMAT_FLAG)

		// Start event loop
		startEventLoop()
	}

	private func loadAndPlay()
	{
		guard let mpv = mpv else { return }
		let urlString = videoURL.absoluteString
		var args: [String?] = ["loadfile", urlString, nil]
		args.withUnsafeMutableBufferPointer
		{ buffer in
			var cArgs = buffer.map { $0.flatMap { UnsafePointer(strdup($0)) } }
			mpv_command(mpv, &cArgs)
			cArgs.forEach { $0.flatMap { free(UnsafeMutablePointer(mutating: $0)) } }
		}
	}

	private func destroyMPV()
	{
		if let mpvGL = mpvGL
		{
			mpv_render_context_free(mpvGL)
			self.mpvGL = nil
		}
		if let mpv = mpv
		{
			mpv_terminate_destroy(mpv)
			self.mpv = nil
		}
	}

	// MARK: - Event Loop

	private func startEventLoop()
	{
		DispatchQueue.global(qos: .userInteractive).async
		{ [weak self] in
			while let self = self, let mpv = self.mpv
			{
				let event = mpv_wait_event(mpv, 0.1)
				guard let ev = event?.pointee else { continue }

				switch ev.event_id
				{
				case MPV_EVENT_PROPERTY_CHANGE:
					guard let prop = ev.data?.assumingMemoryBound(to: mpv_event_property.self).pointee,
						  let name = prop.name.flatMap({ String(cString: $0) }) else { break }

					if name == "time-pos", prop.format == MPV_FORMAT_DOUBLE,
					   let val = prop.data?.assumingMemoryBound(to: Double.self).pointee
					{
						DispatchQueue.main.async { self.updatePosition(val) }
					}
					else if name == "duration", prop.format == MPV_FORMAT_DOUBLE,
							let val = prop.data?.assumingMemoryBound(to: Double.self).pointee
					{
						DispatchQueue.main.async { self.duration = val }
					}
					else if name == "pause", prop.format == MPV_FORMAT_FLAG,
							let val = prop.data?.assumingMemoryBound(to: Int32.self).pointee
					{
						DispatchQueue.main.async { self.updatePauseState(val != 0) }
					}
					else if name == "eof-reached", prop.format == MPV_FORMAT_FLAG,
							let val = prop.data?.assumingMemoryBound(to: Int32.self).pointee,
							val != 0
					{
						DispatchQueue.main.async { self.handlePlaybackEnd() }
					}

				case MPV_EVENT_SHUTDOWN:
					DispatchQueue.main.async { self.handlePlaybackEnd() }
					return

				default:
					break
				}
			}
		}
	}

	// MARK: - Overlay UI

	private func setupOverlay()
	{
		// Overlay container
		overlayView.frame = view.bounds
		overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		overlayView.backgroundColor = .clear
		view.addSubview(overlayView)

		// Top gradient for close button / title
		let topGradient = CAGradientLayer()
		topGradient.colors = [UIColor.black.withAlphaComponent(0.7).cgColor, UIColor.clear.cgColor]
		topGradient.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width * 2, height: 100)
		overlayView.layer.addSublayer(topGradient)

		// Close button
		closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
		closeButton.tintColor = .white
		closeButton.translatesAutoresizingMaskIntoConstraints = false
		closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
		overlayView.addSubview(closeButton)

		// Title label
		titleLabel.text = videoTitle
		titleLabel.textColor = .white
		titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		overlayView.addSubview(titleLabel)

		// Bottom bar
		bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.7)
		bottomBar.translatesAutoresizingMaskIntoConstraints = false
		overlayView.addSubview(bottomBar)

		// Play/Pause button
		playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
		playPauseButton.tintColor = .white
		playPauseButton.translatesAutoresizingMaskIntoConstraints = false
		playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
		bottomBar.addSubview(playPauseButton)

		// Seek bar
		seekBar.minimumTrackTintColor = UIColor(red: 233/255, green: 69/255, blue: 96/255, alpha: 1) // #e94560
		seekBar.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
		seekBar.translatesAutoresizingMaskIntoConstraints = false
		seekBar.addTarget(self, action: #selector(seekBegan), for: .touchDown)
		seekBar.addTarget(self, action: #selector(seekChanged), for: .valueChanged)
		seekBar.addTarget(self, action: #selector(seekEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
		bottomBar.addSubview(seekBar)

		// Time label
		timeLabel.text = "0:00 / 0:00"
		timeLabel.textColor = UIColor.white.withAlphaComponent(0.8)
		timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
		timeLabel.translatesAutoresizingMaskIntoConstraints = false
		bottomBar.addSubview(timeLabel)

		NSLayoutConstraint.activate([
			closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
			closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
			closeButton.widthAnchor.constraint(equalToConstant: 32),
			closeButton.heightAnchor.constraint(equalToConstant: 32),

			titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
			titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 12),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

			bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			bottomBar.heightAnchor.constraint(equalToConstant: 80),

			playPauseButton.leadingAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.leadingAnchor, constant: 16),
			playPauseButton.centerYAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 24),
			playPauseButton.widthAnchor.constraint(equalToConstant: 32),
			playPauseButton.heightAnchor.constraint(equalToConstant: 32),

			seekBar.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 12),
			seekBar.trailingAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.trailingAnchor, constant: -16),
			seekBar.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),

			timeLabel.leadingAnchor.constraint(equalTo: seekBar.leadingAnchor),
			timeLabel.topAnchor.constraint(equalTo: seekBar.bottomAnchor, constant: 4),
		])
	}

	// MARK: - Gestures

	private func setupGestures()
	{
		// Tap to show/hide overlay
		let tapGesture = UITapGestureRecognizer(target: self, action: #selector(overlayTapped))
		overlayView.addGestureRecognizer(tapGesture)

		// Swipe left/right to seek
		let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(swipeToSeek(_:)))
		swipeLeft.direction = .left
		overlayView.addGestureRecognizer(swipeLeft)

		let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(swipeToSeek(_:)))
		swipeRight.direction = .right
		overlayView.addGestureRecognizer(swipeRight)

		tapGesture.require(toFail: swipeLeft)
		tapGesture.require(toFail: swipeRight)
	}

	// MARK: - Actions

	@objc private func closeTapped()
	{
		destroyMPV()
		dismiss(animated: true)
		{
			self.onDismiss?()
		}
	}

	@objc private func playPauseTapped()
	{
		guard let mpv = mpv else { return }
		let newPause: Int32 = isPaused ? 0 : 1
		var value = newPause
		mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &value)
		scheduleOverlayHide()
	}

	@objc private func seekBegan()
	{
		isSeeking = true
		overlayHideTimer?.invalidate()
	}

	@objc private func seekChanged()
	{
		let targetTime = Double(seekBar.value) * duration
		updateTimeLabel(position: targetTime)
	}

	@objc private func seekEnded()
	{
		guard let mpv = mpv else { return }
		let targetTime = Double(seekBar.value) * duration
		let timeStr = String(format: "%.1f", targetTime)
		var args: [String?] = ["seek", timeStr, "absolute", nil]
		args.withUnsafeMutableBufferPointer
		{ buffer in
			var cArgs = buffer.map { $0.flatMap { UnsafePointer(strdup($0)) } }
			mpv_command(mpv, &cArgs)
			cArgs.forEach { $0.flatMap { free(UnsafeMutablePointer(mutating: $0)) } }
		}
		isSeeking = false
		scheduleOverlayHide()
	}

	@objc private func overlayTapped()
	{
		isOverlayVisible.toggle()
		UIView.animate(withDuration: 0.25)
		{
			self.overlayView.alpha = self.isOverlayVisible ? 1.0 : 0.0
		}
		if isOverlayVisible
		{
			scheduleOverlayHide()
		}
	}

	@objc private func swipeToSeek(_ gesture: UISwipeGestureRecognizer)
	{
		guard let mpv = mpv else { return }
		let offset = gesture.direction == .right ? "10" : "-10"
		var args: [String?] = ["seek", offset, "relative", nil]
		args.withUnsafeMutableBufferPointer
		{ buffer in
			var cArgs = buffer.map { $0.flatMap { UnsafePointer(strdup($0)) } }
			mpv_command(mpv, &cArgs)
			cArgs.forEach { $0.flatMap { free(UnsafeMutablePointer(mutating: $0)) } }
		}

		// Briefly show overlay on seek
		if !isOverlayVisible
		{
			isOverlayVisible = true
			UIView.animate(withDuration: 0.25) { self.overlayView.alpha = 1.0 }
		}
		scheduleOverlayHide()
	}

	// MARK: - State Updates

	private func updatePosition(_ pos: Double)
	{
		position = pos
		if !isSeeking && duration > 0
		{
			seekBar.value = Float(pos / duration)
			updateTimeLabel(position: pos)
		}
	}

	private func updatePauseState(_ paused: Bool)
	{
		isPaused = paused
		let icon = paused ? "play.fill" : "pause.fill"
		playPauseButton.setImage(UIImage(systemName: icon), for: .normal)
	}

	private func updateTimeLabel(position: Double)
	{
		let posStr = formatTime(position)
		let durStr = formatTime(duration)
		timeLabel.text = "\(posStr) / \(durStr)"
	}

	private func handlePlaybackEnd()
	{
		isPaused = true
		playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
	}

	// MARK: - Overlay Auto-Hide

	private func scheduleOverlayHide()
	{
		overlayHideTimer?.invalidate()
		overlayHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false)
		{ [weak self] _ in
			guard let self = self, self.isOverlayVisible else { return }
			self.isOverlayVisible = false
			UIView.animate(withDuration: 0.4) { self.overlayView.alpha = 0.0 }
		}
	}

	// MARK: - Helpers

	private func formatTime(_ seconds: Double) -> String
	{
		guard seconds.isFinite && seconds >= 0 else { return "0:00" }
		let totalSeconds = Int(seconds)
		let hours = totalSeconds / 3600
		let minutes = (totalSeconds % 3600) / 60
		let secs = totalSeconds % 60
		if hours > 0
		{
			return String(format: "%d:%02d:%02d", hours, minutes, secs)
		}
		return String(format: "%d:%02d", minutes, secs)
	}
}
