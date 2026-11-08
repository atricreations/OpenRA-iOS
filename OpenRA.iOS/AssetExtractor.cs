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
using System.Security.Cryptography;
using System.Text;
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
			var assetStamp = ComputeAssetStamp();
			if (File.Exists(stampFile) && File.ReadAllText(stampFile).Trim() == assetStamp)
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

			File.WriteAllText(stampFile, assetStamp);
			onProgress?.Invoke("Assets extracted successfully.");
		}

		// Fingerprint = app version + SHA256 of the bundled archive. Including the
		// archive hash means a re-packaged openra-data.zip (e.g. after a mod/yml
		// edit) forces a re-extract WITHOUT bumping the app version. This lets the
		// device dev loop do a plain reinstall (no uninstall -> no profile re-trust)
		// and still pick up fresh assets whenever the archive content changes.
		static string ComputeAssetStamp()
		{
			var info = NSBundle.MainBundle.InfoDictionary;
			var version = $"{info["CFBundleShortVersionString"]}_{info["CFBundleVersion"]}";
			var zipPath = NSBundle.MainBundle.PathForResource(DataZipName, "zip");
			if (zipPath == null)
				return version + "_nozip";

			byte[] hashBytes;
			using (var sha = SHA256.Create())
			using (var stream = File.OpenRead(zipPath))
			{
				hashBytes = sha.ComputeHash(stream);
			}

			var sb = new StringBuilder(hashBytes.Length * 2);
			foreach (var b in hashBytes)
				sb.Append(b.ToString("x2"));
			return version + "_" + sb.ToString();
		}
	}
}
