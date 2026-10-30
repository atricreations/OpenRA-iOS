using System;
using UIKit;

namespace OpenRA
{
	// Hosts the SDL2 game view. The app is locked to landscape via Info.plist, so the
	// drawable is landscape by the time the game starts.
	sealed class ViewController : UIViewController
	{
		public ViewController() : base(UIScreen.MainScreen.Bounds)
		{
			View.BackgroundColor = UIColor.Black;
		}

		public override bool ShouldAutorotate => true;

		public override UIInterfaceOrientationMask SupportedInterfaceOrientations =>
			UIInterfaceOrientationMask.Landscape;

		public void StartGame(Action start)
		{
			// Defer to the next main-loop iteration so UIKit has created the drawable.
			View.BeginInvokeOnMainThread(() =>
			{
				try
				{
					start();
				}
				catch (Exception e)
				{
					Console.WriteLine($"OpenRA iOS startup failed: {e}");
					ExceptionHandler.HandleFatalError(e);
				}
			});
		}
	}
}
