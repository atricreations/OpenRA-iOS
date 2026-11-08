#region Copyright & License Information
/*
 * Copyright (c) The OpenRA Developers and Contributors
 * This file is part of OpenRA, which is free software. It is
 * made available to you under the terms of the GNU General Public License
 * as published by the Free Software Foundation, either version 3 of
 * the License, or (at your option) any later version. For more
 * information, see COPYING.
 */
#endregion

using OpenRA.Primitives;

namespace OpenRA
{
	/// <summary>
	/// Bridge between the on-screen TrackballWidget and the SDL input pump. While a finger
	/// holds the trackball (a camera-pan widget), a second finger touching anywhere else is
	/// delivered to the game as a right mouse click (cancel build, stop, attack-move, ...).
	/// The trackball publishes its held-state and on-screen bounds every tick; Sdl2Input
	/// reads them when mapping second-finger touch events on iOS.
	/// </summary>
	public static class RightClickEmulator
	{
		public static bool TrackballHeld;
		public static Rectangle TrackballRect;
	}
}
