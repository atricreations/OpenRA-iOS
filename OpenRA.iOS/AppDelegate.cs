#region Copyright & License Information
/*
 * Copyright (c) The OpenRA Developers and Contributors
 * This file is part of OpenRA, which is free software. It is
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
using OpenRA.Mods.Cnc.FileSystem;
using UIKit;

namespace OpenRA
{
	[Register("AppDelegate")]
	sealed class AppDelegate : UIApplicationDelegate
	{
		public override UIWindow Window { get; set; }

		readonly ViewController rootViewController = new();

		public override bool FinishedLaunching(UIApplication application, NSDictionary launchOptions)
		{
			// RTS sessions run for a long time without touch input.
			// Keep the display active so iOS does not suspend the simulation mid-session.
			application.IdleTimerDisabled = true;

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
			var audioSession = AVAudioSession.SharedInstance();
			audioSession.SetCategory(AVAudioSessionCategory.Playback, AVAudioSessionCategoryOptions.MixWithOthers);
			audioSession.SetActive(true);

			Window = new UIWindow(UIScreen.MainScreen.Bounds)
			{
				RootViewController = rootViewController
			};
			Window.MakeKeyAndVisible();

			// Return from the app delegate first so UIKit can finish the initial scene and
			// create the drawable. The callback still runs on the main thread, which SDL's
			// UIKit backend requires.
			rootViewController.StartGame(() => IosGameLauncher.Launch());

			return true;
		}

		public override void WillTerminate(UIApplication application)
		{
		}
	}
}
