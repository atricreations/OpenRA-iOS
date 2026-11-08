#region Copyright & License Information
/*
 * Copyright (c) The OpenRA Developers and Contributors
 * This file is part of OpenRA, which is free software. It is made
 * available to you under the terms of the GNU General Public License
 * as published by the Free Software Foundation, either version 3 of
 * the License, or (at your option) any later version. For more
 * information, see COPYING.
 */
#endregion

using System;
using System.Numerics;
using OpenRA.Graphics;
using OpenRA.Primitives;
using OpenRA.Widgets;

namespace OpenRA.Mods.Common.Widgets
{
	/// <summary>
	/// On-screen trackball for panning the in-game camera. Drag the ball to move
	/// the viewport; after release the camera keeps panning with momentum (inertia)
	/// that decays each tick. This is the primary way to navigate the map on a touch
	/// device, where keyboard / edge-scroll / middle-drag are unavailable. Haptic
	/// feedback fires on press and drag on iOS.
	/// </summary>
	public class TrackballWidget : InputWidget
	{
		// Camera pan (screen-px) per pixel of finger drag.
		public float Sensitivity = 1.5f;
		// Per-tick velocity decay applied to momentum after release.
		public float Friction = 0.90f;
		// Velocity (px/tick) below which momentum is considered stopped.
		public float MomentumThreshold = 0.4f;
		// Enable haptic feedback on press/drag (iOS only; no-op elsewhere).
		public bool HapticsEnabled = true;
		public float HapticIntensity = 0.4f;

		readonly WorldRenderer worldRenderer;

		bool dragging;
		int2 lastFingerPos;
		// Camera scroll velocity in screen-px, carried across ticks for momentum.
		Vector2 velocity;

		[ObjectCreator.UseCtor]
		public TrackballWidget(WorldRenderer worldRenderer)
		{
			this.worldRenderer = worldRenderer;
		}

		public TrackballWidget(TrackballWidget other)
			: base(other)
		{
			worldRenderer = other.worldRenderer;
			Sensitivity = other.Sensitivity;
			Friction = other.Friction;
			MomentumThreshold = other.MomentumThreshold;
			HapticsEnabled = other.HapticsEnabled;
			HapticIntensity = other.HapticIntensity;
		}

		// The trackball is a touch affordance; hide it on pointer-based platforms.
		public override void Initialize(WidgetArgs args)
		{
			base.Initialize(args);
			IsVisible = () => Visible && Platform.IsIOS;
		}

		public override bool HandleMouseInput(MouseInput mi)
		{
			if (mi.Button != MouseButton.Left)
				return false;

			switch (mi.Event)
			{
				case MouseInputEvent.Down:
					if (!TakeMouseFocus(mi))
						return false;
					dragging = true;
					lastFingerPos = mi.Location;
					velocity = Vector2.Zero;
					TriggerHaptic();
					return true;

				case MouseInputEvent.Move:
					if (!dragging)
						return false;
					var delta = mi.Location - lastFingerPos;
					if (delta != int2.Zero)
					{
						lastFingerPos = mi.Location;
						// Relative (joystick) metaphor: pushing the ball a direction
						// pans the camera that way. Viewport.Scroll takes screen-px.
						Scroll(delta.ToVector2() * Sensitivity);
						velocity = delta.ToVector2() * Sensitivity;
						TriggerHaptic();
					}
					return true;

				case MouseInputEvent.Up:
					dragging = false;
					YieldMouseFocus(mi);
					// Velocity is retained so Tick() can apply momentum.
					return true;
			}

			return false;
		}

		public override void Tick()
		{
			base.Tick();

			// Publish the held-state and on-screen bounds so the SDL input pump can treat
			// a second finger's tap elsewhere as a right click while this is being held.
			RightClickEmulator.TrackballHeld = HasMouseFocus;
			RightClickEmulator.TrackballRect = RenderBounds;

			if (dragging)
				return;

			if (velocity.Length() <= MomentumThreshold)
			{
				velocity = Vector2.Zero;
				return;
			}

			Scroll(velocity);
			velocity *= Friction;
		}

		void Scroll(Vector2 screenDelta)
		{
			if (screenDelta == Vector2.Zero)
				return;
			if (worldRenderer == null || worldRenderer.Viewport == null)
				return;
			worldRenderer.Viewport.Scroll(screenDelta, false);
		}

		void TriggerHaptic()
		{
			if (HapticsEnabled && Game.Haptics != null)
				Game.Haptics.Play(HapticEffect.LightningStrike, HapticIntensity);
		}

		public override InputWidget Clone() { return new TrackballWidget(this); }

		public override void Draw()
		{
			if (!IsVisible())
				return;

			var rb = RenderBounds;

			// Semi-transparent disc; brightens while being dragged.
			var bg = dragging ? Color.FromArgb(190, 90, 95, 130) : Color.FromArgb(110, 45, 48, 70);
			WidgetUtils.FillEllipseWithColor(rb, bg);

			// Center crosshair so the pan direction reads at a glance.
			var cx = rb.X + rb.Width / 2;
			var cy = rb.Y + rb.Height / 2;
			var arm = Math.Max(2, Math.Min(rb.Width, rb.Height) / 4);
			var cross = Color.FromArgb(225, 235, 235, 245);
			WidgetUtils.FillRectWithColor(new Rectangle(cx - 1, cy - arm, 2, arm * 2), cross);
			WidgetUtils.FillRectWithColor(new Rectangle(cx - arm, cy - 1, arm * 2, 2), cross);
		}
	}
}
