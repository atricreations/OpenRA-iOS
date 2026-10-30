#region Copyright & License Information
/*
 * Copyright (c) The OpenRA Developers and Contributors
 * This file is part of OpenRA, which is free software. It is
 * made available to you under the terms of the GNU General Public License
 * as published by the Free Software Foundation, either version 3 of
 * the License, or (at your option) any later version.
 * For more information, see COPYING.
 *
 * Derived from the NUKEHOUR iOS port (https://github.com/kveinjay-google/NUKEHOUR),
 * GNU General Public License v3. See NOTICE for details.
 */
#endregion

using System;
using OpenRA.Primitives;

namespace OpenRA.Platforms.Default
{
	public sealed class IosPlatform : IPlatform
	{
		public IPlatformWindow CreateWindow(
			Size size, WindowMode windowMode, float scaleModifier, int vertexBatchSize, int indexBatchSize, int videoDisplay, GLProfile profile)
		{
			return new Sdl2PlatformWindow(size, windowMode, scaleModifier, vertexBatchSize, indexBatchSize, videoDisplay, profile);
		}

		public ISoundEngine CreateSound(string device)
		{
			try
			{
				return new Sdl2SoundEngine();
			}
			catch (Exception e)
			{
				Log.Write("sound", $"SDL iOS audio unavailable; continuing without audio: {e}");
				return new DummySoundEngine();
			}
		}

		public IHapticEngine CreateHaptics()
		{
			return new IosHapticEngine();
		}

		public IFont CreateFont(byte[] data)
		{
			return new FreeTypeFont(data);
		}
	}
}
