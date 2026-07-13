using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Interop;
using OverCUE.Core;

namespace OverCUE.Windows;

internal sealed class RawInputService : IDisposable
{
    private const int WM_INPUT = 0x00FF;
    private const uint RID_INPUT = 0x10000003;
    private const uint RIDI_DEVICENAME = 0x20000007;
    private const uint RIDEV_INPUTSINK = 0x00000100;
    private const uint RIDEV_DEVNOTIFY = 0x00002000;
    private readonly ACK05KeyboardDecoder decoder = new();
    private readonly object sync = new();
    private readonly HashSet<ACK05Key> pressedKeys = [];
    private readonly Dictionary<ushort, ACK05Key> activeVirtualKeys = [];
    private HwndSource? source;
    private System.Threading.Timer? flushTimer;

    public event Action<ACK05Event>? InputDecoded;
    public event Action<IReadOnlySet<ACK05Key>>? PressedKeysChanged;
    public event Action<bool>? ConnectionChanged;

    public void Attach(System.Windows.Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        source = HwndSource.FromHwnd(handle) ?? throw new InvalidOperationException("WPF window source is unavailable.");
        source.AddHook(WindowProcedure);
        var devices = new[] { new RAWINPUTDEVICE(0x01, 0x06, RIDEV_INPUTSINK | RIDEV_DEVNOTIFY, handle) };
        if (!RegisterRawInputDevices(devices, 1, (uint)Marshal.SizeOf<RAWINPUTDEVICE>()))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not register ACK05 keyboard input.");
        flushTimer = new System.Threading.Timer(_ => Flush(), null, 10, 10);
        ConnectionChanged?.Invoke(true);
    }

    public void Dispose()
    {
        flushTimer?.Dispose();
        flushTimer = null;
        source?.RemoveHook(WindowProcedure);
        source = null;
    }

    private nint WindowProcedure(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message == WM_INPUT) ProcessInput(lParam);
        return nint.Zero;
    }

    private void ProcessInput(nint rawInput)
    {
        uint size = 0;
        var headerSize = (uint)Marshal.SizeOf<RAWINPUTHEADER>();
        if (GetRawInputData(rawInput, RID_INPUT, nint.Zero, ref size, headerSize) == uint.MaxValue) return;
        var buffer = Marshal.AllocHGlobal((int)size);
        try
        {
            if (GetRawInputData(rawInput, RID_INPUT, buffer, ref size, headerSize) == uint.MaxValue) return;
            var header = Marshal.PtrToStructure<RAWINPUTHEADER>(buffer);
            if (header.Type != 1 || !IsACK05(header.Device)) return;
            var keyboard = Marshal.PtrToStructure<RAWKEYBOARD>(buffer + (int)headerSize);
            // The low-level reserved-key service owns F13-F24 so driver-generated input and
            // device-backed Raw Input cannot produce duplicate ACK05 events.
            if (keyboard.VirtualKey is >= 0x7C and <= 0x87) return;
            var isDown = keyboard.Message is 0x0100 or 0x0104;
            IReadOnlyList<ACK05Event> events;
            lock (sync)
                events = decoder.Process(new(DateTimeOffset.UtcNow, keyboard.VirtualKey, keyboard.MakeCode,
                    isDown));
            if (!isDown && activeVirtualKeys.Remove(keyboard.VirtualKey, out var releasedKey))
            {
                pressedKeys.Remove(releasedKey);
                PublishPressedKeys();
            }
            foreach (var value in events) PublishDecoded(value, keyboard.VirtualKey, isDown);
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    private void Flush()
    {
        IReadOnlyList<ACK05Event> events;
        lock (sync) events = decoder.Flush(DateTimeOffset.UtcNow);
        foreach (var value in events) PublishDecoded(value, 0, false);
    }

    private void PublishDecoded(ACK05Event value, ushort virtualKey, bool isDown)
    {
        InputDecoded?.Invoke(value);
        if (value is not ACK05Event.KeyDown key) return;
        if (isDown && virtualKey != 0)
        {
            activeVirtualKeys[virtualKey] = key.Key;
            if (pressedKeys.Add(key.Key)) PublishPressedKeys();
            return;
        }
        pressedKeys.Add(key.Key);
        PublishPressedKeys();
        _ = Task.Run(async () =>
        {
            await Task.Delay(60);
            lock (sync)
            {
                if (pressedKeys.Remove(key.Key)) PublishPressedKeys();
            }
        });
    }

    private void PublishPressedKeys() => PressedKeysChanged?.Invoke(pressedKeys.ToHashSet());

    private static bool IsACK05(nint device)
    {
        uint length = 0;
        if (GetRawInputDeviceInfo(device, RIDI_DEVICENAME, nint.Zero, ref length) == uint.MaxValue || length == 0) return false;
        var name = new StringBuilder((int)length + 1);
        if (GetRawInputDeviceInfo(device, RIDI_DEVICENAME, name, ref length) == uint.MaxValue) return false;
        return name.ToString().Contains("28BD", StringComparison.OrdinalIgnoreCase)
            && name.ToString().Contains("0202", StringComparison.OrdinalIgnoreCase);
    }

    [StructLayout(LayoutKind.Sequential)] private readonly record struct RAWINPUTDEVICE(ushort UsagePage, ushort Usage, uint Flags, nint Target);
    [StructLayout(LayoutKind.Sequential)] private struct RAWINPUTHEADER { public uint Type, Size; public nint Device, WParam; }
    [StructLayout(LayoutKind.Sequential)]
    private struct RAWKEYBOARD
    { public ushort MakeCode, Flags, Reserved, VirtualKey; public uint Message, ExtraInformation; }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterRawInputDevices(
        [In] RAWINPUTDEVICE[] devices, uint count, uint size);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetRawInputData(
        nint input, uint command, nint data, ref uint size, uint headerSize);
    [DllImport("user32.dll", EntryPoint = "GetRawInputDeviceInfoW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetRawInputDeviceInfo(nint device, uint command, nint data, ref uint size);
    [DllImport("user32.dll", EntryPoint = "GetRawInputDeviceInfoW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetRawInputDeviceInfo(nint device, uint command, StringBuilder data, ref uint size);
}
