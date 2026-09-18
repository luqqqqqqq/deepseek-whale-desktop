using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

public class WhaleHost : Window
{
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT pt);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] static extern uint GetDpiForSystem();
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szDevice;
    }

    const int VK_LBUTTON = 0x01;

    WebView2 wv;
    DispatcherTimer dragTimer;
    double lastX, lastY;
    double dpiScale = 1.0;
    IntPtr hwnd;
    CoreWebView2 core;
    bool hostLeft = false;
    string snapMode = "ratio";
    double rL = 10, rT = 0, rR = 10, rB = 15, rF = 50;
    double pL = 80, pT = 0, pR = 80, pB = 80, pF = -1;
    bool locked = false;
    bool scrollGapOn = false;
    double scrollGapPx = 17;

    public WhaleHost(string url)
    {
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = false;   // 关键：不用 WS_EX_LAYERED，WebView2 才能收到输入
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        Width = 280;
        Height = 280;
        WindowStartupLocation = WindowStartupLocation.Manual;
        try
        {
            var wa0 = SystemParameters.WorkArea;
            Left = wa0.Right - Width;
            Top = wa0.Bottom - Height;
        }
        catch { }
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;

        var chrome = new WindowChrome();
        chrome.GlassFrameThickness = new Thickness(-1);
        chrome.CaptionHeight = 0;
        chrome.ResizeBorderThickness = new Thickness(0);
        chrome.CornerRadius = new CornerRadius(0);
        chrome.UseAeroCaptionButtons = false;
        WindowChrome.SetWindowChrome(this, chrome);

        SetWindowTemplate();

        wv = new WebView2();
        wv.DefaultBackgroundColor = System.Drawing.Color.Transparent;
        wv.HorizontalAlignment = HorizontalAlignment.Stretch;
        wv.VerticalAlignment = VerticalAlignment.Stretch;

        var grid = new Grid();
        grid.Children.Add(wv);
        Content = grid;

        SourceInitialized += OnSourceInitialized;

        Loaded += async (s, e) =>
        {
            try
            {
                string profile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "wv2-profile");
                var env = await CoreWebView2Environment.CreateAsync(null, profile, null);
                await wv.EnsureCoreWebView2Async(env);
                Log("CoreWebView2 ready");
                core = wv.CoreWebView2;
                wv.CoreWebView2.WebMessageReceived += OnWebMessage;
                wv.CoreWebView2.Navigate(url);
                Log("Navigate: " + url);
                wv.Focus();
            }
            catch (Exception ex)
            {
                Log("LoadFailed: " + ex);
            }
        };
    }

    void SetWindowTemplate()
    {
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.BackgroundProperty, Brushes.Transparent);
        border.SetValue(Border.SnapsToDevicePixelsProperty, true);
        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        border.AppendChild(presenter);

        var template = new ControlTemplate(typeof(Window));
        template.VisualTree = border;
        Template = template;
    }

    void OnSourceInitialized(object sender, EventArgs e)
    {
        try
        {
            hwnd = new WindowInteropHelper(this).Handle;
            dpiScale = GetWindowScale();
            Log("SourceInitialized dpiScale=" + dpiScale);
        }
        catch { }
        if (dpiScale <= 0) dpiScale = 1.0;
    }

    double GetWindowScale()
    {
        try
        {
            if (hwnd != IntPtr.Zero)
            {
                uint dpi = GetDpiForWindow(hwnd);
                if (dpi > 0) return dpi / 96.0;
            }
        }
        catch { }
        try
        {
            uint dpi = GetDpiForSystem();
            if (dpi > 0) return dpi / 96.0;
        }
        catch { }
        return 1.0;
    }

    RECT GetWorkAreaDip()
    {
        try
        {
            if (hwnd != IntPtr.Zero)
            {
                IntPtr mon = MonitorFromWindow(hwnd, 2); // MONITOR_DEFAULTTONEAREST
                if (mon != IntPtr.Zero)
                {
                    MONITORINFO mi = new MONITORINFO();
                    mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
                    if (GetMonitorInfo(mon, ref mi))
                    {
                        double s = GetWindowScale();
                        if (s <= 0) s = 1.0;
                        RECT r;
                        r.Left = (int)Math.Round(mi.rcWork.Left / s);
                        r.Top = (int)Math.Round(mi.rcWork.Top / s);
                        r.Right = (int)Math.Round(mi.rcWork.Right / s);
                        r.Bottom = (int)Math.Round(mi.rcWork.Bottom / s);
                        return r;
                    }
                }
            }
        }
        catch { }

        RECT f;
        var wa = SystemParameters.WorkArea;
        f.Left = (int)wa.Left;
        f.Top = (int)wa.Top;
        f.Right = (int)wa.Right;
        f.Bottom = (int)wa.Bottom;
        return f;
    }

    void SetEdge(bool left)
    {
        try
        {
            if (core == null) return;
            string js = "(function(){var r=document.querySelector('.dshwv-root'); if(r){ r.classList." +
                (left ? "add" : "remove") + "('dshwv-host-left'); }})();";
            core.ExecuteScriptAsync(js);
        }
        catch { }
    }

    void UpdateEdge()
    {
        try
        {
            if (core == null) return;
            if (snapMode == "off")
            {
                if (hostLeft) { hostLeft = false; SetEdge(false); }
                return;
            }
            RECT wa = GetWorkAreaDip();
            double flipX = GetFlipX(wa);
            double centerX = Left + Width / 2.0;
            bool wantLeft = centerX < flipX;
            if (wantLeft != hostLeft)
            {
                hostLeft = wantLeft;
                SetEdge(wantLeft);
            }
        }
        catch { }
    }

    double GetFlipX(RECT wa)
    {
        double w = Math.Max(1, wa.Right - wa.Left);
        if (snapMode == "px")
        {
            if (pF < 0) return wa.Left + w / 2.0;
            return wa.Left + pF;
        }
        return wa.Left + w * (rF / 100.0);
    }

    void OnWebMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        string msg = null;
        try { msg = e.TryGetWebMessageAsString(); } catch { }
        if (msg == "dragstart") StartDrag();
        else if (msg == "dragend") EndDrag();
        else if (msg == "close") Close();
        else if (msg == "lock:1") locked = true;
        else if (msg == "lock:0") locked = false;
        else if (msg != null && msg.StartsWith("snapcfg:")) ParseSnapCfg(msg.Substring("snapcfg:".Length));
        else if (msg != null && msg.StartsWith("scrollgap:")) ParseScrollGap(msg.Substring("scrollgap:".Length));
        else if (msg != null && msg.StartsWith("setsize:"))
        {
            string[] parts = msg.Substring("setsize:".Length).Split(',');
            double w, h;
            if (parts.Length >= 2 && double.TryParse(parts[0], out w) && double.TryParse(parts[1], out h))
                ApplySize(w, h);
        }
    }

    void ApplySize(double w, double h)
    {
        try
        {
            if (double.IsNaN(w) || double.IsNaN(h) || w <= 0 || h <= 0) return;
            w = Math.Max(140, Math.Min(1400, w));
            h = Math.Max(140, Math.Min(1400, h));
            double right = Left + Width;
            double bottom = Top + Height;
            Width = w;
            Height = h;
            Left = right - w;
            Top = bottom - h;
            ClampPosition();
        }
        catch { }
    }

    void ParseSnapCfg(string s)
    {
        try
        {
            string[] p = s.Split(',');
            if (p.Length < 11) return;
            snapMode = p[0];
            double.TryParse(p[1], out rL);
            double.TryParse(p[2], out rT);
            double.TryParse(p[3], out rR);
            double.TryParse(p[4], out rB);
            double.TryParse(p[5], out rF);
            double.TryParse(p[6], out pL);
            double.TryParse(p[7], out pT);
            double.TryParse(p[8], out pR);
            double.TryParse(p[9], out pB);
            double.TryParse(p[10], out pF);
            SnapToEdge();
        }
        catch { }
    }

    void ParseScrollGap(string s)
    {
        try
        {
            string[] p = s.Split(',');
            if (p.Length < 2) return;
            int on;
            if (int.TryParse(p[0], out on)) scrollGapOn = on != 0;
            double px;
            if (double.TryParse(p[1], out px)) scrollGapPx = Math.Max(0, px);
            ClampPosition();
        }
        catch { }
    }

    void EndDrag()
    {
        StopDrag();
        SnapToEdge();
    }

    void SnapToEdge()
    {
        try
        {
            if (snapMode == "off") { ClampPosition(); return; }
            RECT wa = GetWorkAreaDip();
            double w = Math.Max(1, wa.Right - wa.Left);
            double h = Math.Max(1, wa.Bottom - wa.Top);
            double rightGap = (scrollGapOn && scrollGapPx > 0) ? scrollGapPx : 0;
            double rightEdge = wa.Right - rightGap;
            double lz, tz, rz, bz;
            if (snapMode == "px")
            {
                lz = pL; tz = pT; rz = pR; bz = pB;
            }
            else
            {
                lz = w * rL / 100.0;
                tz = h * rT / 100.0;
                rz = w * rR / 100.0;
                bz = h * rB / 100.0;
            }
            if (Left < wa.Left + lz) Left = wa.Left;
            else if (Left + Width > rightEdge - rz) Left = rightEdge - Width;
            if (Top < wa.Top + tz) Top = wa.Top;
            else if (Top + Height > wa.Bottom - bz) Top = wa.Bottom - Height;
            ClampPosition();
        }
        catch { }
    }

    void StartDrag()
    {
        try
        {
            if (locked) return;
            if (dragTimer != null) return;
            POINT p;
            GetCursorPos(out p);
            lastX = p.X;
            lastY = p.Y;
            dragTimer = new DispatcherTimer();
            dragTimer.Interval = TimeSpan.FromMilliseconds(15);
            dragTimer.Tick += OnDragTick;
            dragTimer.Start();
        }
        catch { }
    }

    void OnDragTick(object sender, EventArgs e)
    {
        try
        {
            // 用物理按键状态判断，避免 WebView2 子窗口吃掉鼠标消息导致误判松手
            if ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0)
            {
                StopDrag();
                return;
            }
            POINT p;
            GetCursorPos(out p);
            double s = GetWindowScale();
            if (s <= 0) s = dpiScale;
            double dx = (p.X - lastX) / s;
            double dy = (p.Y - lastY) / s;
            if (dx != 0 || dy != 0)
            {
                Left += dx;
                Top += dy;
                dpiScale = s;
                ClampPosition();
            }
            lastX = p.X;
            lastY = p.Y;
        }
        catch { StopDrag(); }
    }

    void ClampPosition()
    {
        try
        {
            RECT wa = GetWorkAreaDip();
            double rightGap = (scrollGapOn && scrollGapPx > 0) ? scrollGapPx : 0;
            double maxLeft = Math.Max(wa.Left, wa.Right - rightGap - Width);
            double maxTop = Math.Max(wa.Top, wa.Bottom - Height);
            Left = Math.Min(Math.Max(Left, wa.Left), maxLeft);
            Top = Math.Min(Math.Max(Top, wa.Top), maxTop);
            UpdateEdge();
        }
        catch { }
    }

    void StopDrag()
    {
        try
        {
            if (dragTimer != null)
            {
                dragTimer.Stop();
                dragTimer = null;
            }
        }
        catch { }
    }

    static void Log(string msg)
    {
        try
        {
            File.AppendAllText(
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "host.log"),
                DateTime.Now.ToString("s") + " " + msg + Environment.NewLine);
        }
        catch { }
    }

    [STAThread]
    static void Main(string[] args)
    {
        try
        {
            // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
            if (!SetProcessDpiAwarenessContext(new IntPtr(-4)))
                SetProcessDPIAware();
        }
        catch
        {
            try { SetProcessDPIAware(); } catch { }
        }
        string url = args.Length > 0 ? args[0] : "http://127.0.0.1:9876/";
        var app = new Application();
        app.Run(new WhaleHost(url));
    }
}
