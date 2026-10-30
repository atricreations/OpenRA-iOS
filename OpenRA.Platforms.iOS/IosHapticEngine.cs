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
using UIKit;

namespace OpenRA.Platforms.Default
{
	sealed class IosHapticEngine : IHapticEngine
	{
		readonly UIImpactFeedbackGenerator nuclear = new(UIImpactFeedbackStyle.Heavy);
		readonly UIImpactFeedbackGenerator lightning = new(UIImpactFeedbackStyle.Medium);

		public void Play(HapticEffect effect, float intensity)
		{
			var strength = Math.Clamp(intensity, 0f, 1f);
			if (strength <= 0f)
				return;

			UIApplication.SharedApplication.BeginInvokeOnMainThread(() =>
			{
				var generator = effect == HapticEffect.NuclearExplosion ? nuclear : lightning;
				generator.Prepare();
				generator.ImpactOccurred((nfloat)strength);
			});
		}

		public void Dispose()
		{
			nuclear.Dispose();
			lightning.Dispose();
		}
	}
}
