using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace MineXRayHD
{
    internal sealed class ItemInfo
    {
        public readonly string Label;
        public readonly SolidColorBrush Brush;
        public readonly bool Important;

        public ItemInfo(string label, string color, bool important = false)
        {
            Label = label;
            Brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
            Brush.Freeze();
            Important = important;
        }
    }

    internal sealed class TileInfo
    {
        public int Col;
        public int Row;
        public int Type;
        public int Rock;
        public int Dirt;
    }

    internal sealed class OverlayData
    {
        public bool Active;
        public string Mine = "";
        public int Floor;
        public int CameraX;
        public int CameraY;
        public string Revision = "";
        public readonly List<TileInfo> Tiles = new List<TileInfo>();
    }

    internal static class StateReader
    {
        public static bool TryRead(string path, out OverlayData data)
        {
            data = null;
            try
            {
                string[] lines;
                using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete))
                using (var reader = new StreamReader(stream, new UTF8Encoding(false, true)))
                {
                    var list = new List<string>();
                    string line;
                    while ((line = reader.ReadLine()) != null)
                    {
                        list.Add(line);
                    }
                    lines = list.ToArray();
                }

                if (lines.Length < 3)
                {
                    return false;
                }
                string[] begin = lines[0].Split('\t');
                string[] end = lines[lines.Length - 1].Split('\t');
                if (begin.Length != 2 || end.Length != 2 || begin[0] != "B" || end[0] != "E"
                    || begin[1] != end[1])
                {
                    return false;
                }

                var result = new OverlayData { Revision = begin[1] };
                for (int i = 1; i < lines.Length - 1; i++)
                {
                    string[] fields = lines[i].Split('\t');
                    if (fields.Length == 0)
                    {
                        continue;
                    }
                    int value;
                    switch (fields[0])
                    {
                        case "A":
                            result.Active = fields.Length >= 2 && fields[1] == "1";
                            break;
                        case "M":
                            if (fields.Length >= 3 && Int32.TryParse(fields[2], out value))
                            {
                                result.Mine = fields[1];
                                result.Floor = value;
                            }
                            break;
                        case "C":
                            int cameraY;
                            if (fields.Length >= 3 && Int32.TryParse(fields[1], out value)
                                && Int32.TryParse(fields[2], out cameraY))
                            {
                                result.CameraX = value;
                                result.CameraY = cameraY;
                            }
                            break;
                        case "T":
                            int row, type, rock, dirt;
                            if (fields.Length >= 6 && Int32.TryParse(fields[1], out value)
                                && Int32.TryParse(fields[2], out row)
                                && Int32.TryParse(fields[3], out type)
                                && Int32.TryParse(fields[4], out rock)
                                && Int32.TryParse(fields[5], out dirt))
                            {
                                result.Tiles.Add(new TileInfo {
                                    Col = value, Row = row, Type = type, Rock = rock, Dirt = dirt
                                });
                            }
                            break;
                    }
                }
                data = result;
                return true;
            }
            catch (IOException)
            {
                return false;
            }
            catch (UnauthorizedAccessException)
            {
                return false;
            }
            catch (DecoderFallbackException)
            {
                return false;
            }
        }
    }

    internal sealed class OverlaySurface : FrameworkElement
    {
        private static readonly Typeface LabelTypeface = new Typeface(
            new FontFamily("Microsoft YaHei UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);
        private static readonly SolidColorBrush LabelBackground = MakeBrush(0x28, 0, 0, 0);
        private static readonly SolidColorBrush HeaderBackground = MakeBrush(0x70, 0, 0, 0);
        private static readonly SolidColorBrush Outline = MakeBrush(0xE8, 0, 0, 0);
        private static readonly SolidColorBrush White = MakeBrush(0xFF, 255, 255, 255);

        private static readonly Dictionary<int, ItemInfo> Rocks = new Dictionary<int, ItemInfo> {
            { 0x0A, new ItemInfo("转", "#FFFF40FF", true) },
            { 0x0C, new ItemInfo("废", "#FFB0B0B0") },
            { 0x0D, new ItemInfo("铜", "#FFFFA050") },
            { 0x0E, new ItemInfo("银", "#FFFFFFFF") },
            { 0x0F, new ItemInfo("金", "#FFFFD700") },
            { 0x10, new ItemInfo("秘", "#FF70A0FF") },
            { 0x11, new ItemInfo("奥", "#FFFFFFFF") },
            { 0x12, new ItemInfo("刚", "#FF40FFFF") },
            { 0x13, new ItemInfo("月", "#FFD0D8FF") },
            { 0x14, new ItemInfo("玫", "#FFFFB0C8") },
            { 0x15, new ItemInfo("粉", "#FFFF50A8", true) },
            { 0x16, new ItemInfo("亚", "#FF40FF70", true) },
            { 0x17, new ItemInfo("贤", "#FFFFFFFF", true) },
            { 0x18, new ItemInfo("钻", "#FFC8FFFF") },
            { 0x19, new ItemInfo("绿", "#FF40FF70") },
            { 0x1A, new ItemInfo("红", "#FFFF5050") },
            { 0x1B, new ItemInfo("黄", "#FFFFFF40") },
            { 0x1C, new ItemInfo("橄", "#FFA0FF50") },
            { 0x1D, new ItemInfo("萤", "#FF30F0A0") },
            { 0x1E, new ItemInfo("玛", "#FFFFA040") },
            { 0x1F, new ItemInfo("紫", "#FFD080FF") },
            { 0x20, new ItemInfo("女", "#FFFFFFFF", true) },
            { 0x21, new ItemInfo("河", "#FF40FF40", true) },
        };

        private static readonly Dictionary<int, ItemInfo> Dirt = new Dictionary<int, ItemInfo> {
            { 0x01, new ItemInfo("梯", "#FFFF9000", true) },
            { 0x02, new ItemInfo("钱", "#FFFFFF00") },
            { 0x03, new ItemInfo("果", "#FFFF3030", true) },
            { 0x04, new ItemInfo("镰", "#FFFF60D0", true) },
            { 0x05, new ItemInfo("锄", "#FFFF60D0", true) },
            { 0x06, new ItemInfo("斧", "#FFFF60D0", true) },
            { 0x07, new ItemInfo("锤", "#FFFF60D0", true) },
            { 0x08, new ItemInfo("水", "#FFFF60D0", true) },
            { 0x09, new ItemInfo("竿", "#FFFF60D0", true) },
            { 0x0B, new ItemInfo("草", "#FFB0FF80") },
            { 0x22, new ItemInfo("谱", "#FFFFFFFF", true) },
        };

        public OverlayData Data { get; private set; }

        public OverlaySurface()
        {
            IsHitTestVisible = false;
            SnapsToDevicePixels = false;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Ideal);
            TextOptions.SetTextRenderingMode(this, TextRenderingMode.ClearType);
        }

        public void SetData(OverlayData data)
        {
            Data = data;
            InvalidateVisual();
        }

        protected override void OnRender(DrawingContext drawingContext)
        {
            base.OnRender(drawingContext);
            drawingContext.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, ActualWidth, ActualHeight));
            if (Data == null || !Data.Active || ActualWidth < 1 || ActualHeight < 1)
            {
                return;
            }

            double sx = ActualWidth / 240.0;
            double sy = ActualHeight / 160.0;
            DrawHeader(drawingContext, sx, sy);

            foreach (TileInfo tile in Data.Tiles)
            {
                double nativeX = 24 + tile.Col * 16 - Data.CameraX;
                double nativeY = 55 + tile.Row * 16 - Data.CameraY;
                if (nativeX <= -15 || nativeX >= 240 || nativeY <= -15 || nativeY >= 160)
                {
                    continue;
                }

                ItemInfo rock = null;
                ItemInfo dirt = null;
                bool showRock = tile.Type == 4 && Rocks.TryGetValue(tile.Rock, out rock);
                bool showDirt = Dirt.TryGetValue(tile.Dirt, out dirt);
                bool dirtIsMain = showDirt && (!showRock || (dirt.Important && tile.Dirt != 0x01));

                if (dirtIsMain)
                {
                    DrawLabel(drawingContext, dirt, nativeX, nativeY, sx, sy);
                    if (showRock)
                    {
                        DrawRockCue(drawingContext, rock, nativeX, nativeY, sx, sy);
                    }
                }
                else if (showRock)
                {
                    DrawLabel(drawingContext, rock, nativeX, nativeY, sx, sy);
                    if (showDirt)
                    {
                        DrawGroundCue(drawingContext, dirt, tile.Dirt, nativeX, nativeY, sx, sy);
                    }
                }
                else if (showDirt)
                {
                    DrawLabel(drawingContext, dirt, nativeX, nativeY, sx, sy);
                }
            }
        }

        private void DrawHeader(DrawingContext dc, double sx, double sy)
        {
            string text = Data.Mine + Data.Floor.ToString(CultureInfo.InvariantCulture) + "层";
            var formatted = MakeText(text, 5.3 * sy, White);
            double width = formatted.Width + 5 * sx;
            double height = Math.Max(10 * sy, formatted.Height + sy);
            var rect = new Rect(240 * sx - width, 0, width, height);
            dc.DrawRoundedRectangle(HeaderBackground, null, rect, 1.5 * sx, 1.5 * sy);
            DrawOutlinedText(dc, formatted,
                new Point(rect.X + (rect.Width - formatted.Width) / 2,
                    rect.Y + (rect.Height - formatted.Height) / 2),
                White, Math.Max(0.55, 0.18 * sy));
        }

        private static void DrawLabel(DrawingContext dc, ItemInfo item, double x, double y,
            double sx, double sy)
        {
            var rect = new Rect((x + 2) * sx, (y + 2) * sy, 12 * sx, 12 * sy);
            dc.DrawRoundedRectangle(LabelBackground, null, rect, 1.2 * sx, 1.2 * sy);
            var formatted = MakeText(item.Label, 7.0 * sy, item.Brush);
            var origin = new Point(
                rect.X + (rect.Width - formatted.Width) / 2,
                rect.Y + (rect.Height - formatted.Height) / 2);
            DrawOutlinedText(dc, formatted, origin, item.Brush, Math.Max(0.65, 0.22 * sy));
        }

        private static void DrawGroundCue(DrawingContext dc, ItemInfo item, int id, double x, double y,
            double sx, double sy)
        {
            if (id == 0x01)
            {
                dc.DrawRectangle(item.Brush, null, new Rect((x + 10) * sx, (y + 13) * sy, 5 * sx, 2 * sy));
                dc.DrawRectangle(item.Brush, null, new Rect((x + 13) * sx, (y + 10) * sy, 2 * sx, 5 * sy));
            }
            else
            {
                dc.DrawRoundedRectangle(item.Brush, null,
                    new Rect((x + 11) * sx, (y + 11) * sy, 4 * sx, 4 * sy), sx * 0.6, sy * 0.6);
            }
        }

        private static void DrawRockCue(DrawingContext dc, ItemInfo item, double x, double y,
            double sx, double sy)
        {
            dc.DrawRoundedRectangle(item.Brush, null,
                new Rect(x * sx, y * sy, 4 * sx, 4 * sy), sx * 0.6, sy * 0.6);
        }

        private static FormattedText MakeText(string text, double size, Brush brush)
        {
#pragma warning disable 618
            return new FormattedText(text, CultureInfo.GetCultureInfo("zh-CN"),
                FlowDirection.LeftToRight, LabelTypeface, size, brush);
#pragma warning restore 618
        }

        private static void DrawOutlinedText(DrawingContext dc, FormattedText text, Point origin,
            Brush fill, double outlineWidth)
        {
            Geometry geometry = text.BuildGeometry(origin);
            var pen = new Pen(Outline, outlineWidth) { LineJoin = PenLineJoin.Round };
            pen.Freeze();
            dc.DrawGeometry(fill, pen, geometry);
        }

        private static SolidColorBrush MakeBrush(byte a, byte r, byte g, byte b)
        {
            var brush = new SolidColorBrush(Color.FromArgb(a, r, g, b));
            brush.Freeze();
            return brush;
        }
    }

    internal sealed class OverlayWindow : Window
    {
        private readonly Process _mgba;
        private readonly string _statePath;
        private readonly OverlaySurface _surface;
        private readonly DispatcherTimer _timer;
        private IntPtr _handle;
        private IntPtr _mainWindow;
        private long _lastWriteTicks = -1;
        private long _lastLength = -1;
        private NativeMethods.RECT _lastViewport;
        private bool _nativeVisible;

        public OverlayWindow(Process mgba, string statePath)
        {
            _mgba = mgba;
            _statePath = statePath;
            _surface = new OverlaySurface();

            Title = "Mine X-Ray HD Overlay";
            Width = 1;
            Height = 1;
            Left = -20000;
            Top = -20000;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            ShowActivated = false;
            Topmost = true;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            Focusable = false;
            Content = _surface;

            SourceInitialized += OnSourceInitialized;
            Closed += delegate { _timer.Stop(); };
            _timer = new DispatcherTimer(DispatcherPriority.Render) {
                Interval = TimeSpan.FromMilliseconds(33)
            };
            _timer.Tick += OnTick;
            _timer.Start();
        }

        private void OnSourceInitialized(object sender, EventArgs e)
        {
            _handle = new WindowInteropHelper(this).Handle;
            long style = NativeMethods.GetWindowLongPtr(_handle, NativeMethods.GWL_EXSTYLE).ToInt64();
            style |= NativeMethods.WS_EX_TRANSPARENT | NativeMethods.WS_EX_TOOLWINDOW
                | NativeMethods.WS_EX_NOACTIVATE;
            NativeMethods.SetWindowLongPtr(_handle, NativeMethods.GWL_EXSTYLE, new IntPtr(style));
            NativeMethods.ShowWindow(_handle, NativeMethods.SW_HIDE);
        }

        private void OnTick(object sender, EventArgs e)
        {
            if (_mgba.HasExited)
            {
                Close();
                return;
            }

            if (_mainWindow == IntPtr.Zero || !NativeMethods.IsWindow(_mainWindow))
            {
                _mgba.Refresh();
                _mainWindow = _mgba.MainWindowHandle;
            }
            if (_mainWindow == IntPtr.Zero || NativeMethods.IsIconic(_mainWindow))
            {
                HideNative();
                return;
            }

            IntPtr foreground = NativeMethods.GetForegroundWindow();
            IntPtr foregroundRoot = NativeMethods.GetAncestor(foreground, NativeMethods.GA_ROOT);
            if (foregroundRoot != _mainWindow)
            {
                HideNative();
                return;
            }

            IntPtr renderWindow = NativeMethods.FindLargestVisibleChild(_mainWindow);
            if (renderWindow == IntPtr.Zero)
            {
                renderWindow = _mainWindow;
            }
            NativeMethods.RECT childRect;
            if (!NativeMethods.GetWindowRect(renderWindow, out childRect))
            {
                HideNative();
                return;
            }
            NativeMethods.RECT viewport = CalculateViewport(childRect);
            PositionNative(viewport);
            ReadStateIfChanged();
            ShowNative();
        }

        private void ReadStateIfChanged()
        {
            try
            {
                var info = new FileInfo(_statePath);
                if (!info.Exists)
                {
                    return;
                }
                long ticks = info.LastWriteTimeUtc.Ticks;
                long length = info.Length;
                if (ticks == _lastWriteTicks && length == _lastLength)
                {
                    return;
                }

                OverlayData data;
                if (StateReader.TryRead(_statePath, out data))
                {
                    _lastWriteTicks = ticks;
                    _lastLength = length;
                    _surface.SetData(data);
                }
            }
            catch (IOException)
            {
                // Lua may be replacing the small state file; retry on the next timer tick.
            }
        }

        private static NativeMethods.RECT CalculateViewport(NativeMethods.RECT source)
        {
            int width = source.Right - source.Left;
            int height = source.Bottom - source.Top;
            const double targetAspect = 240.0 / 160.0;
            int viewportWidth;
            int viewportHeight;
            int x = source.Left;
            int y = source.Top;
            if ((double)width / Math.Max(1, height) > targetAspect)
            {
                viewportHeight = height;
                viewportWidth = (int)Math.Round(height * targetAspect);
                x += (width - viewportWidth) / 2;
            }
            else
            {
                viewportWidth = width;
                viewportHeight = (int)Math.Round(width / targetAspect);
                y += (height - viewportHeight) / 2;
            }
            return new NativeMethods.RECT {
                Left = x, Top = y, Right = x + viewportWidth, Bottom = y + viewportHeight
            };
        }

        private void PositionNative(NativeMethods.RECT viewport)
        {
            if (viewport.Left == _lastViewport.Left && viewport.Top == _lastViewport.Top
                && viewport.Right == _lastViewport.Right && viewport.Bottom == _lastViewport.Bottom)
            {
                return;
            }
            _lastViewport = viewport;
            NativeMethods.SetWindowPos(_handle, NativeMethods.HWND_TOPMOST,
                viewport.Left, viewport.Top, viewport.Right - viewport.Left, viewport.Bottom - viewport.Top,
                NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW);
            _surface.InvalidateVisual();
        }

        private void ShowNative()
        {
            if (!_nativeVisible)
            {
                NativeMethods.ShowWindow(_handle, NativeMethods.SW_SHOWNOACTIVATE);
                _nativeVisible = true;
            }
        }

        private void HideNative()
        {
            if (_nativeVisible)
            {
                NativeMethods.ShowWindow(_handle, NativeMethods.SW_HIDE);
                _nativeVisible = false;
            }
        }
    }

    internal static class NativeMethods
    {
        internal const int GWL_EXSTYLE = -20;
        internal const long WS_EX_TRANSPARENT = 0x00000020L;
        internal const long WS_EX_TOOLWINDOW = 0x00000080L;
        internal const long WS_EX_NOACTIVATE = 0x08000000L;
        internal const uint SWP_NOACTIVATE = 0x0010;
        internal const uint SWP_SHOWWINDOW = 0x0040;
        internal const int SW_HIDE = 0;
        internal const int SW_SHOWNOACTIVATE = 4;
        internal const uint GA_ROOT = 2;
        internal static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential)]
        internal struct RECT
        {
            internal int Left;
            internal int Top;
            internal int Right;
            internal int Bottom;
        }

        internal delegate bool EnumWindowProc(IntPtr handle, IntPtr parameter);

        [DllImport("user32.dll")]
        internal static extern bool GetWindowRect(IntPtr handle, out RECT rect);

        [DllImport("user32.dll")]
        internal static extern bool IsWindow(IntPtr handle);

        [DllImport("user32.dll")]
        internal static extern bool IsWindowVisible(IntPtr handle);

        [DllImport("user32.dll")]
        internal static extern bool IsIconic(IntPtr handle);

        [DllImport("user32.dll")]
        internal static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        internal static extern IntPtr GetAncestor(IntPtr handle, uint flags);

        [DllImport("user32.dll")]
        internal static extern bool EnumChildWindows(IntPtr parent, EnumWindowProc callback, IntPtr parameter);

        [DllImport("user32.dll")]
        internal static extern bool SetWindowPos(IntPtr handle, IntPtr insertAfter, int x, int y,
            int width, int height, uint flags);

        [DllImport("user32.dll")]
        internal static extern bool ShowWindow(IntPtr handle, int command);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
        private static extern IntPtr GetWindowLongPtr64(IntPtr handle, int index);

        [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
        private static extern int GetWindowLong32(IntPtr handle, int index);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
        private static extern IntPtr SetWindowLongPtr64(IntPtr handle, int index, IntPtr value);

        [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
        private static extern int SetWindowLong32(IntPtr handle, int index, int value);

        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        [DllImport("user32.dll", EntryPoint = "SetProcessDpiAwarenessContext")]
        private static extern bool SetProcessDpiAwarenessContextInternal(IntPtr context);

        internal static IntPtr GetWindowLongPtr(IntPtr handle, int index)
        {
            return IntPtr.Size == 8 ? GetWindowLongPtr64(handle, index) : new IntPtr(GetWindowLong32(handle, index));
        }

        internal static IntPtr SetWindowLongPtr(IntPtr handle, int index, IntPtr value)
        {
            return IntPtr.Size == 8
                ? SetWindowLongPtr64(handle, index, value)
                : new IntPtr(SetWindowLong32(handle, index, value.ToInt32()));
        }

        internal static void EnableDpiAwareness()
        {
            try
            {
                if (SetProcessDpiAwarenessContextInternal(new IntPtr(-4)))
                {
                    return;
                }
            }
            catch (EntryPointNotFoundException)
            {
            }
            SetProcessDPIAware();
        }

        internal static IntPtr FindLargestVisibleChild(IntPtr parent)
        {
            IntPtr best = IntPtr.Zero;
            long bestArea = 0;
            EnumChildWindows(parent, delegate(IntPtr child, IntPtr unused) {
                RECT rect;
                if (IsWindowVisible(child) && GetWindowRect(child, out rect))
                {
                    long area = (long)Math.Max(0, rect.Right - rect.Left)
                        * Math.Max(0, rect.Bottom - rect.Top);
                    if (area > bestArea)
                    {
                        bestArea = area;
                        best = child;
                    }
                }
                return true;
            }, IntPtr.Zero);
            return best;
        }
    }

    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            if (args.Length == 2 && args[0] == "--render-test")
            {
                RenderTest(args[1]);
                return;
            }

            bool ownsMutex;
            using (var mutex = new Mutex(true, "Local\\MineXRayHDOverlay", out ownsMutex))
            {
                if (!ownsMutex)
                {
                    MessageBox.Show("矿场高清浮层已经在运行。", "Mine X-Ray",
                        MessageBoxButton.OK, MessageBoxImage.Information);
                    return;
                }

                try
                {
                    NativeMethods.EnableDpiAwareness();
                    string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
                    string mgbaPath = Path.Combine(baseDirectory, "emulator", "mGBA.exe");
                    string luaPath = Path.Combine(baseDirectory, "mine_xray_mgba.lua");
                    string romPath = Path.Combine(baseDirectory, "game", "game.gba");
                    string statePath = Path.Combine(Path.GetTempPath(), "mgba_mine_xray_state.txt");

                    if (!File.Exists(mgbaPath) || !File.Exists(luaPath) || !File.Exists(romPath))
                    {
                        MessageBox.Show("找不到 emulator\\mGBA.exe、Lua 脚本或 game\\game.gba。\n请按 README 的目录结构放置文件。",
                            "Mine X-Ray", MessageBoxButton.OK, MessageBoxImage.Error);
                        return;
                    }
                    try
                    {
                        if (File.Exists(statePath))
                        {
                            File.Delete(statePath);
                        }
                    }
                    catch (IOException)
                    {
                    }

                    var startInfo = new ProcessStartInfo {
                        FileName = mgbaPath,
                        Arguments = "-C \"savestatePath=" + Path.GetDirectoryName(romPath).Replace('\\', '/')
                            + "\" --script \"" + luaPath + "\" \"" + romPath + "\"",
                        WorkingDirectory = Path.GetDirectoryName(mgbaPath),
                        UseShellExecute = false,
                    };
                    using (Process mgba = Process.Start(startInfo))
                    {
                        var application = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
                        var overlay = new OverlayWindow(mgba, statePath);
                        application.Run(overlay);
                    }

                    try
                    {
                        if (File.Exists(statePath))
                        {
                            File.Delete(statePath);
                        }
                    }
                    catch (IOException)
                    {
                    }
                }
                catch (Exception exception)
                {
                    MessageBox.Show("高清浮层启动失败：\n" + exception.Message,
                        "Mine X-Ray", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }

        private static void RenderTest(string outputPath)
        {
            string statePath = Path.Combine(Path.GetTempPath(), "mgba_mine_xray_state.txt");
            OverlayData data;
            if (!StateReader.TryRead(statePath, out data))
            {
                throw new InvalidOperationException("无法读取浮层测试状态。");
            }

            const int width = 1200;
            const int height = 800;
            var surface = new OverlaySurface { Width = width, Height = height };
            surface.SetData(data);
            surface.Measure(new Size(width, height));
            surface.Arrange(new Rect(0, 0, width, height));
            surface.UpdateLayout();
            var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(surface);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (var stream = new FileStream(outputPath, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                encoder.Save(stream);
            }
        }
    }
}

