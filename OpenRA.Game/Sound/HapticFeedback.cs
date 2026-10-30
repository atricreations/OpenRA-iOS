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

namespace OpenRA
{
	public enum HapticEffect
	{
		NuclearExplosion,
		LightningStrike
	}

	public interface IHapticEngine : IDisposable
	{
		void Play(HapticEffect effect, float intensity);
	}

	public sealed class NullHapticEngine : IHapticEngine
	{
		public void Play(HapticEffect effect, float intensity) { }
		public void Dispose() { }
	}

	public static class HapticStrengthPolicy
	{
		const int ReferenceDistance = 6826;
		const int MaximumDistance = 136533;

		public static float Resolve(float audioVolume, WPos listenerPosition, WPos sourcePosition)
		{
			var volume = Math.Clamp(audioVolume, 0f, 1f);
			if (volume == 0f)
				return 0f;

			var distance = Math.Clamp((sourcePosition - listenerPosition).Length, ReferenceDistance, MaximumDistance);
			var distanceGain = ReferenceDistance / (float)(ReferenceDistance + distance - ReferenceDistance);
			return volume * distanceGain;
		}
	}
}
