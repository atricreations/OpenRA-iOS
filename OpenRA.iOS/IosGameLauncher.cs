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
using Foundation;

namespace OpenRA
{
	static class IosGameLauncher
	{
		public static void Launch()
		{
			NativeLibraryResolver.Initialize();

			var bundlePath = NSBundle.MainBundle.ResourcePath;
			if (string.IsNullOrEmpty(bundlePath))
				throw new InvalidOperationException("App bundle resource path is unavailable.");

			// Engine data (glsl, mods) is extracted from the bundle into a writable
			// directory; user data (settings, saves, content, logs) lives in the support dir.
			var engineDir = Path.Combine(
				Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "OpenRA", "Game");
			var supportDir = Path.Combine(
				Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "OpenRA", "Support");
			Directory.CreateDirectory(engineDir);
			Directory.CreateDirectory(supportDir);

			Platform.OverrideEngineDir(engineDir);
			Platform.OverrideSupportDir(supportDir);

			AssetExtractor.EnsureAssetsExtracted(engineDir);

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

			Game.InitializeAndRun(args);
		}
	}
}
