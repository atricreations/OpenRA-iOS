using System;
using System.IO;

namespace OpenRA
{
	// Debug aid: file-based startup tracing. .NET Console output on the iOS
	// simulator is not captured by simctl or the unified log, so startup
	// markers are appended to a file in the app's Documents directory.
	static class StartupTrace
	{
		static readonly object Gate = new();

		public static void Log(string message)
		{
			try
			{
				var dir = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
				if (string.IsNullOrEmpty(dir))
					return;
				lock (Gate)
					File.AppendAllText(Path.Combine(dir, "startup-trace.log"),
						$"{DateTime.UtcNow:O} {message}{Environment.NewLine}");
			}
			catch
			{
				// Tracing must never break startup.
			}
		}
	}
}
