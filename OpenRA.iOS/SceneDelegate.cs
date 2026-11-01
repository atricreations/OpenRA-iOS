using Foundation;
using UIKit;

namespace OpenRA
{
	// Scene-based lifecycle host. Apps linked against the iOS 26+ SDK are
	// required to adopt scenes (UIKit otherwise traps in
	// NoSceneLifecycleAdoption), so a scene manifest is present in Info.plist
	// and this class is the configured delegate.
	//
	// The 27.1 bindings renamed the connect callback: the ObjC selector is
	// "scene:willConnectToSession:options:" (C# method "WillConnect"), not the
	// legacy "windowScene:willConnectWithSessionOptions:" C# name.
	//
	// Note: on this runtime the plist-referenced delegate is not always
	// connected by UIKit; AppDelegate runs a fallback that creates the game
	// window itself if this callback never fires. Both paths funnel through
	// IosGameLauncher.StartGameForScene, which guards against double startup.
	[Register("SceneDelegate")]
	sealed class SceneDelegate : UIWindowSceneDelegate
	{
		public SceneDelegate()
		{
			StartupTrace.Log("SceneDelegate ctor");
		}

		public override void WillConnect(UIScene scene, UISceneSession session, UISceneConnectionOptions options)
		{
			StartupTrace.Log("WillConnect entered");
			IosGameLauncher.StartGameForScene((UIWindowScene)scene);
		}
	}
}
