using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

internal static class OpenGbaWithLatestSave
{
    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKey);

    [STAThread]
    private static void Main(string[] args)
    {
        try
        {
            if (args.Length < 1 || !File.Exists(args[0]))
            {
                MessageBox.Show("找不到要打开的 GBA ROM。", "mGBA", MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return;
            }

            string romPath = Path.GetFullPath(args[0]);
            string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
            string mgbaPath = Path.Combine(baseDirectory, "emulator", "mGBA.exe");
            if (!File.Exists(mgbaPath))
            {
                MessageBox.Show("找不到 emulator\\mGBA.exe。请按 README 的目录结构放置 mGBA。", "mGBA",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            // 按住 Shift 再双击 ROM 时跳过即时存档，直接让游戏读取 .sav。
            bool skipInstantState = (GetAsyncKeyState(0x10) & 0x8000) != 0;
            string latestState = skipInstantState ? null : FindNewestState(romPath);
            string stateDirectory = Path.GetDirectoryName(romPath);
            string statePathOption = "-C " + Quote("savestatePath="
                + stateDirectory.Replace('\\', '/')) + " ";

            string commandLine = latestState == null
                ? statePathOption + Quote(romPath)
                : statePathOption + "-t " + Quote(latestState) + " " + Quote(romPath);

            Process.Start(new ProcessStartInfo {
                FileName = mgbaPath,
                Arguments = commandLine,
                WorkingDirectory = Path.GetDirectoryName(mgbaPath),
                UseShellExecute = false,
            });
        }
        catch (Exception exception)
        {
            MessageBox.Show("启动游戏失败：\n" + exception.Message, "mGBA", MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private static string FindNewestState(string romPath)
    {
        string directory = Path.GetDirectoryName(romPath);
        string stem = Path.GetFileNameWithoutExtension(romPath);
        string latest = null;
        DateTime latestTime = DateTime.MinValue;
        for (int slot = 1; slot <= 9; slot++)
        {
            string candidate = Path.Combine(directory, stem + ".ss" + slot);
            if (!File.Exists(candidate))
            {
                continue;
            }
            DateTime time = File.GetLastWriteTimeUtc(candidate);
            if (time > latestTime)
            {
                latest = candidate;
                latestTime = time;
            }
        }
        return latest;
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }
}

