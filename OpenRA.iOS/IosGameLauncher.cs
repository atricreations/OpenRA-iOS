#region Copyright & License Information
/*
 * Copyright (c) The OpenRA Developers and Contributors
 * This file is part of OpenRA, which is free software. It is
 * made available to you under the terms of the GNU General Public License
 * as published by the Free Software Foundation, either version 3 of
 * the License, or (at your option) any later version.
 * For more information, see COPYING.
 *
 * Launch sequence modeled on OpenRA.Android (https://github.com/nurbsn/OpenRA.Android),
 * GNU General Public License v3. See NOTICE for details.
 */
#endregion

using System;
using System.IO;
using System.Threading;
using Foundation;
using SDL2;
using UIKit;

namespace OpenRA
{
	static class IosGameLauncher
	{
		static int started;
		static readonly ViewController RootViewController = new();

		// Single owner of the game window and launch. The scene delegate and the
		// app-delegate fallback both funnel through here; the first caller wins.
		public static void StartGameForScene(UIWindowScene scene)
		{
			if (Interlocked.Exchange(ref started, 1) == 1)
			{
				StartupTrace.Log("StartGameForScene: already started, backing off");
				return;
			}

			// SDL creates its own UIWindow and attaches it to the scene (the
			// "Scene-attach fix" in the native SDL), making the game window the
			// scene's primary window. The root view controller is used only as a
			// main-thread dispatch anchor, not to host a competing window.
			StartupTrace.Log("Scene connected, scheduling game launch (SDL owns the window)");
			// Defer to the next main-thread cycle.
			RootViewController.View.BeginInvokeOnMainThread(Launch);
		}

		public static bool GameStarted => Volatile.Read(ref started) == 1;

		public static void Launch()
		{
			StartupTrace.Log("Launch started");
			NativeLibraryResolver.Initialize();
			StartupTrace.Log("NativeLibraryResolver initialized");

			// Apple SDL builds are compiled with SDL_MAIN_NEEDED: SDL_Init refuses to
			// run until the application's main() has signalled readiness, which the
			// SDL_main.h shim normally does for us. This app ships its own managed
			// main(), so signal it here before any SDL subsystem (audio, video) inits.
			SDL.SDL_SetMainReady();
			// Consume SDL finger events directly instead of also synthesising
			// duplicate mouse events for every touch.
			SDL.SDL_SetHint(SDL.SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
			StartupTrace.Log("SDL_SetMainReady done");

			var bundlePath = NSBundle.MainBundle.ResourcePath;
			if (string.IsNullOrEmpty(bundlePath))
				throw new InvalidOperationException("App bundle resource path is unavailable.");
			StartupTrace.Log($"Bundle path: {bundlePath}");

			// Engine data (glsl, mods) is extracted from the bundle into a writable
			// directory; user data (settings, saves, content, logs) lives in the support dir.
			var engineDir = Path.Combine(
				Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "OpenRA", "Game");
			var supportDir = Path.Combine(
				Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "OpenRA", "Support");
			Directory.CreateDirectory(engineDir);
			Directory.CreateDirectory(supportDir);
			StartupTrace.Log($"Dirs created: {engineDir} | {supportDir}");

			Platform.OverrideEngineDir(engineDir);
			Platform.OverrideSupportDir(supportDir);

			StartupTrace.Log("Asset extraction starting");
			AssetExtractor.EnsureAssetsExtracted(engineDir);
			StartupTrace.Log("Asset extraction complete");

			// Proven mobile launch arguments (from OpenRA.Android).
			var args = new[]
			{
				"Game.Mod=ra",
				"Graphics.GLProfile=Embedded",
				"Graphics.Mode=Fullscreen",
				"Graphics.CapFramerate=True",
				"Graphics.MaxFramerate=60",
				"Game.MouseControlStyle=Classic",
				"Game.MouseScroll=Standard",
				"Game.ViewportEdgeScroll=False",
				"Game.UseAlternateScrollButton=False",
				"Game.IntroductionPromptVersion=2"
			};

			StartupTrace.Log("Calling Game.InitializeAndRun");
			Game.InitializeAndRun(args);
		}
	}
}
