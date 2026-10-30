using System;
using OpenRA.Mods.Cnc.FileSystem;

namespace OpenRA
{
	// OpenRA discovers these loaders from the mod manifest at runtime. Referencing
	// their constructors here makes the iOS AOT compiler emit the entry points
	// needed by reflection without changing the desktop mod-loading path.
	// (Active once Phase 8 switches the build from interpreter to AOT.)
	internal static class AotPreserve
	{
		static readonly MixLoader Mix = new();
		static readonly BigLoader Big = new();
		static readonly MegV3Loader MegV3 = new();
		static readonly PakFileLoader PakFile = new();

		public static void Touch()
		{
			GC.KeepAlive(Mix);
			GC.KeepAlive(Big);
			GC.KeepAlive(MegV3);
			GC.KeepAlive(PakFile);
		}
	}
}
