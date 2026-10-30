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
using System.IO;
using System.IO.Compression;
using Foundation;

namespace OpenRA
{
	public static class AssetExtractor
	{
		const string DataZipName = "openra-data";
		const string VersionStampFile = ".extracted_version";

		public static void EnsureAssetsExtracted(string targetDir, Action<string> onProgress = null)
		{
			Directory.CreateDirectory(targetDir);

			var stampFile = Path.Combine(targetDir, VersionStampFile);
			var appVersion = AppVersionStamp();
			if (File.Exists(stampFile) && File.ReadAllText(stampFile).Trim() == appVersion)
			{
				onProgress?.Invoke("Assets up to date.");
				return;
			}

			var zipPath = NSBundle.MainBundle.PathForResource(DataZipName, "zip");
			if (zipPath == null)
				throw new FileNotFoundException($"Bundled asset archive '{DataZipName}.zip' not found in the app bundle.");

			onProgress?.Invoke("Extracting game assets...");

			using (var archive = ZipFile.OpenRead(zipPath))
			{
				var targetRoot = Path.GetFullPath(targetDir);
				var total = archive.Entries.Count;
				var current = 0;

				foreach (var entry in archive.Entries)
				{
					current++;

					var destPath = Path.GetFullPath(Path.Combine(targetRoot, entry.FullName));
					if (!destPath.StartsWith(targetRoot, StringComparison.Ordinal))
						throw new IOException($"Unsafe path in asset archive: {entry.FullName}");

					if (string.IsNullOrEmpty(entry.Name))
					{
						Directory.CreateDirectory(destPath);
						continue;
					}

					var parentDir = Path.GetDirectoryName(destPath);
					if (!string.IsNullOrEmpty(parentDir))
						Directory.CreateDirectory(parentDir);

					entry.ExtractToFile(destPath, overwrite: true);

					if (current % 100 == 0)
						onProgress?.Invoke($"Extracting assets ({current}/{total})...");
				}
			}

			File.WriteAllText(stampFile, appVersion);
			onProgress?.Invoke("Assets extracted successfully.");
		}

		static string AppVersionStamp()
		{
			var info = NSBundle.MainBundle.InfoDictionary;
			return $"{info["CFBundleShortVersionString"]}_{info["CFBundleVersion"]}";
		}
	}
}
