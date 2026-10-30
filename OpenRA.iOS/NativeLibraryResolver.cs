#region Copyright & License Information
/*
 * Copyright (c) The OpenRA Developers and Contributors
 * This file is part of OpenRA, which is free software. It is
 * made available to you under the terms of the GNU General Public License
 * as published by the Free Software Foundation, either version 3 of
 * the License, or (at your option) any later version.
 * For more information, see COPYING.
 *
 * Pattern derived from OpenRA.Android (https://github.com/nurbsn/OpenRA.Android),
 * GNU General Public License v3. See NOTICE for details.
 */
#endregion

using System;
using System.Reflection;
using System.Runtime.InteropServices;
using Foundation;

namespace OpenRA
{
	public static class NativeLibraryResolver
	{
		static bool initialized;
		static IntPtr mainExecutableHandle;

		public static void Initialize()
		{
			if (initialized)
				return;

			initialized = true;

			// Register resolver for all current and future assemblies
			AppDomain.CurrentDomain.AssemblyLoad += (_, e) => RegisterForAssembly(e.LoadedAssembly);

			foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
				RegisterForAssembly(assembly);
		}

		static void RegisterForAssembly(Assembly assembly)
		{
			try
			{
				NativeLibrary.SetDllImportResolver(assembly, ResolveLibrary);
			}
			catch (InvalidOperationException)
			{
				// Resolver already set for this assembly
			}
			catch (Exception ex)
			{
				Console.WriteLine($"[NativeLibraryResolver] Error setting resolver for {assembly.FullName}: {ex.Message}");
			}
		}

		static IntPtr ResolveLibrary(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
		{
			var name = libraryName;

			if (name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
				name = name[..^4];
			else if (name.EndsWith(".dylib", StringComparison.OrdinalIgnoreCase))
				name = name[..^6];

			var candidate = name switch
			{
				"SDL2" => "libSDL2.dylib",
				"freetype6" or "freetype" => "libfreetype.dylib",
				"lua51" or "lua5.1" or "lua" => "liblua51.dylib",
				"soft_oal" or "openal" or "OpenAL32" => "libopenal.dylib",
				_ => null
			};

			if (candidate != null)
			{
				// Dynamic-library layout: the dylib ships inside the app bundle.
				if (NativeLibrary.TryLoad(candidate, assembly, searchPath, out var handle) && handle != IntPtr.Zero)
					return handle;
			}

			// Static-archive layout: the library is linked into the main executable,
			// so its symbols resolve through the app's own image.
			return MainExecutableHandle();
		}

		static IntPtr MainExecutableHandle()
		{
			if (mainExecutableHandle == IntPtr.Zero)
			{
				var path = NSBundle.MainBundle.ExecutablePath;
				if (!string.IsNullOrEmpty(path) && !NativeLibrary.TryLoad(path, out mainExecutableHandle))
					mainExecutableHandle = IntPtr.Zero;
			}

			return mainExecutableHandle;
		}
	}
}
