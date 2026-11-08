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
using System.Collections.Generic;
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
		System.Threading.Timer audioReassertTimer;
		int audioReassertCount;

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
			// Evidence: exactly what the ObjC runtime lookup UIKit performs can see.
			StartupTrace.Log($"ObjC lookup: 'SceneDelegate' -> {LookupObjCClass("SceneDelegate")} | 'OpenRA.SceneDelegate' -> {LookupObjCClass("OpenRA.SceneDelegate")}");

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

			// Route game audio through the ambient category so it mixes with other apps
			// AND respects the device's silent switch / ringer settings (the playback
			// category, previously used, ignores the silent switch).
			try
			{
				var audioSession = AVAudioSession.SharedInstance();
				audioSession.SetCategory(AVAudioSessionCategory.Ambient, AVAudioSessionCategoryOptions.MixWithOthers);
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
			var scenes = UIApplication.SharedApplication.ConnectedScenes;

			// Log scene state ~once per second so a black screen can be triaged
			// from startup-trace.log alone (no scene vs scene-with-window).
			if (attempt % 4 == 0 || attempt >= 36)
				StartupTrace.Log($"Fallback probe (attempt {attempt}): appState={UIApplication.SharedApplication.ApplicationState} | {DescribeScenes(scenes)}");

			// Prefer a windowless scene, but a scene that already holds a window
			// (e.g. the system/launch window) is usable too: SDL creates its own
			// UIWindow and attaches it to the scene, which then comes to the front.
			UIWindowScene? target = null;
			foreach (var s in scenes)
			{
				if (s is UIWindowScene ws && ws.Windows.Length == 0)
				{
					target = ws;
					break;
				}
			}
			if (target == null)
			{
				foreach (var s in scenes)
				{
					if (s is UIWindowScene ws)
					{
						target = ws;
						break;
					}
				}
			}

			if (target != null)
			{
				StartupTrace.Log($"Fallback: starting game in scene (attempt {attempt}, windows={target.Windows.Length}, state={target.ActivationState})");
				// Start re-asserting Ambient before the (blocking) game loop runs,
				// so the background timer keeps the silent-switch behavior even if
				// SDL's audio init re-sets the category.
				StartAudioReassert();
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
				StartupTrace.Log($"Fallback: giving up, no usable scene after 10s | {DescribeScenes(scenes)}");
			}
		}

		static string DescribeScenes(NSSet scenes)
		{
			var parts = new List<string>();
			foreach (var s in scenes)
			{
				var ws = s as UIWindowScene;
			var us = s as UIScene;
			string state = us == null ? "?" : us.ActivationState.ToString();
			int winCount = ws == null ? -1 : ws.Windows.Length;
			parts.Add($"{s.GetType().Name}(state={state},windows={winCount})");
			}
			return parts.Count == 0 ? "scenes=0" : $"scenes={parts.Count} [{string.Join(" ", parts)}]";
		}

		// Mirrors what UIKit does to resolve UISceneDelegateClass (NSClassFromString).
		static string LookupObjCClass(string name)
		{
			try
			{
				nint handle = Class.GetHandle(name);
				if (handle == IntPtr.Zero)
					return "NULL";
				return new Class(handle).Name ?? "?";
			}
			catch (Exception e)
			{
				return $"EXC:{e.Message}";
			}
		}

		// Re-assert the Ambient audio category so the app respects the silent
		// switch. SDL's native CoreAudio backend may re-set the category to
		// Playback when it initializes audio; re-asserting periodically (on a
		// background thread, since the game loop blocks the main run loop)
		// overrides that for the first 60 seconds, covering audio init.
		void StartAudioReassert()
		{
			ReassertAmbient();
			audioReassertCount = 0;
			audioReassertTimer = new System.Threading.Timer(_ =>
			{
				ReassertAmbient();
				audioReassertCount++;
				if (audioReassertCount >= 60)
				{
					audioReassertTimer?.Dispose();
					audioReassertTimer = null;
				}
			}, null, 1000, 1000);
		}

		void ReassertAmbient()
		{
			try
			{
				var session = AVAudioSession.SharedInstance();
				// Always re-assert Ambient (a no-op if already Ambient) so it survives
				// any SDL override.
				session.SetCategory(AVAudioSessionCategory.Ambient, AVAudioSessionCategoryOptions.MixWithOthers);
			}
			catch (Exception e)
			{
				Console.WriteLine($"ReassertAmbient failed: {e}");
			}
		}

		public override void WillTerminate(UIApplication application)
		{
		}
	}
}
