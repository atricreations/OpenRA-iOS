using System;
using UIKit;

namespace OpenRA
{
	// Hosts the SDL2 game view. The app is locked to landscape via Info.plist, so the
	// drawable is landscape by the time the game starts.
	sealed class ViewController : UIViewController
	{
		// No frame-based init: scene-based UIKit gives the view its size.
		public ViewController()
		{
		}

		// Landscape lock comes from Info.plist (UISupportedInterfaceOrientations).
		// iOS 26+ removed the UIViewController orientation property overrides.
		public override bool ShouldAutorotate() => true;

		public void StartGame(Action start)
		{
			try
			{
				View.BeginInvokeOnMainThread(() =>
				{
					StartupTrace.Log("StartGame callback running");
					try
					{
						start();
					}
					catch (Exception e)
					{
						Console.WriteLine($"OpenRA iOS startup failed: {e}");
						StartupTrace.Log($"Startup failed: {e}");
						ExceptionHandler.HandleFatalError(e);
					}
				});
			}
			catch (Exception e)
			{
				Console.WriteLine($"OpenRA iOS scheduling failed: {e}");
				StartupTrace.Log($"Scheduling failed: {e}");
			}
		}
	}
}
