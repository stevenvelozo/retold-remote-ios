import UIKit
import Capacitor

/// Custom Capacitor bridge view controller that registers retold-remote
/// native plugins (NativePlayer, ServerManager).
///
/// After running `npx cap add ios`, update the Xcode project to use this
/// class instead of the default CAPBridgeViewController:
///
/// 1. Copy this file into ios/App/App/
/// 2. Copy NativePlayerPlugin.swift into ios/App/App/
/// 3. Copy ServerManagerPlugin.swift into ios/App/App/
/// 4. In Main.storyboard, change the view controller's class to
///    RetoldBridgeViewController (or set it in AppDelegate)
///
/// For MPVKit integration:
/// 1. In Xcode: File > Add Package Dependencies
/// 2. Enter: https://github.com/mpvkit/MPVKit
/// 3. Select the appropriate version
/// 4. Update NativePlayerPlugin.swift to use MPVKit for video playback
class RetoldBridgeViewController: CAPBridgeViewController
{
	override open func capacitorDidLoad()
	{
		bridge?.registerPluginInstance(NativePlayerPlugin())
		bridge?.registerPluginInstance(ServerManagerPlugin())
	}
}
