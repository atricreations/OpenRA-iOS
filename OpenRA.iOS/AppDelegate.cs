#region Copyright & License Information
/*
 * Copyright (c) The OpenRA Developers and Contributors
 * This file is part of OpenRA. It is free software. It is
 * made available to you under the terms of the GNU General Public License
 * as published by the Free Software Foundation, either version 3 of
 * the License, or (at your option) any later version.
 * For more information, see COPYING.
 *
 * Structure derived from the NUKEHOUR iOS port
 * (https://github.com/kveinjay-google/NUKEHOUR), GNU General Public License v3.
 * See NOTICE for details.
 */
#endregion

using System;
using AVFoundation;
using Foundation;
using ObjCRuntime;
using OpenRA.Mods.Cnc.FileSystem;
using UIKit;

namespace OpenRA
{
	[Register("AppDelegate")]
	sealed class AppDelegate : UIApplicationDelegate
	{
		public override bool FinishedLaunching(UIApplication application, NSDictionary launchOptions)
		{
			StartupTrace.Log("FinishedLaunching entered");

			// RTS sessions run for a long time without touch input.
			// Keep the display active so iOS does not suspend the simulation mid-session.
			application.IdleTimerDisabled = true;

			// UIKit resolves "UISceneDelegateClass" from Info.plist through the ObjC
			// runtime when the scene activates, which happens after this method
			// returns. Explicitly register the app assembly with the runtime and
			// touch the type so its ObjC class is materialized before the lookup.
			Runtime.RegisterAssembly(typeof(SceneDelegate).Assembly);
			StartupTrace.Log("RegisterAssembly(app) done");
			_ = new SceneDelegate();
			StartupTrace.Log("SceneDelegate touched");

			Platform.OverrideHostPlatform(PlatformType.iOS);

			// AOT/interpreter hosts cannot rely on the desktop assembly-scan path for
			// file-format loaders, so provide a static factory for the ones the mods use.
			ObjectCreator.LoaderFactoryOverride = format => format switch
			{
				"Mix" => new MixLoader(),
				"Big" => new BigLoader(),
				"MegV3" => new MegV3Loader(),
				"PakFile" => new PakFileLoader(),
				_ => null
			};

			// Statically register the iOS platform instead of loading OpenRA.Platforms.Default.dll.
			Game.PlatformFactoryOverride = _ => new OpenRA.Platforms.Default.IosPlatform();

			// Route game audio through the playback category so it is mixed with other apps.
			try
			{
				var audioSession = AVAudioSession.SharedInstance();
				audioSession.SetCategory(AVAudioSessionCategory.Playback, AVAudioSessionCategoryOptions.MixWithOthers);
				audioSession.SetActive(true);
			}
			catch (Exception e)
			{
				Console.WriteLine($"Audio session configuration failed (continuing): {e}");
			}

			// The game window is normally created by SceneDelegate when the scene
			// connects. On this runtime the plist-referenced delegate is not always
			// connected by UIKit, so poll for the connected scene and create the
			// window ourselves if the delegate never does.
			EnsureGameStarted(0);

			return true;
		}

		// Runs on the main thread and re-schedules itself until the game window
		// exists: either SceneDelegate created it (GameStarted) or we do it here.
		void EnsureGameStarted(int attempt)
		{
			UIWindowScene? target = null;
			foreach (var s in UIApplication.SharedApplication.ConnectedScenes)
			{
				if (s is UIWindowScene ws && ws.Windows.Length == 0)
				{
					target = ws;
					break;
				}
			}

			if (target != null)
			{
				StartupTrace.Log($"Fallback: creating window for scene (attempt {attempt})");
				IosGameLauncher.StartGameForScene(target);
				return;
			}

			if (IosGameLauncher.GameStarted)
				return;

			if (attempt < 40)
			{
				// Non-repeating timer on the main run loop.
				_ = NSTimer.CreateScheduledTimer(TimeSpan.FromMilliseconds(250), _ => EnsureGameStarted(attempt + 1));
			}
			else
			{
				StartupTrace.Log("Fallback: giving up, no windowless scene after 10s");
			}
		}

		public override void WillTerminate(UIApplication application)
		{
		}
	}
}
