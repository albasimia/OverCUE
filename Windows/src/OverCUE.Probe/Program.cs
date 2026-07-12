using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using OverCUE.Core;

if (!OperatingSystem.IsWindows())
{
    Console.Error.WriteLine("OverCUE.Probe must be run on Windows.");
    return 1;
}

var options = ProbeOptions.Parse(args);
Console.WriteLine("OverCUE ACK05 Raw Input Probe");
Console.WriteLine($"filter={(options.AllHid ? "all HID" : "VID_28BD/PID_0202")}, output={(options.JsonLines ? "jsonl" : "text")}");
Console.WriteLine("This probe observes input; it does not suppress legacy keyboard input. Press Ctrl+C to stop.");

using var probe = new RawInputProbe(options);
probe.Run();
return 0;

internal sealed record ProbeOptions(bool AllHid, bool JsonLines)
{
    public static ProbeOptions Parse(string[] arguments)
    {
        var unknown = arguments.Where(value => value is not "--all-hid" and not "--jsonl").ToArray();
        if (unknown.Length > 0)
        {
            throw new ArgumentException($"Unknown argument: {string.Join(", ", unknown)}");
        }

        return new ProbeOptions(arguments.Contains("--all-hid"), arguments.Contains("--jsonl"));
    }
}

internal sealed class RawInputProbe : IDisposable
{
    private const ushort VendorID = 0x28BD;
    private const ushort ProductID = 0x0202;

    private const uint WM_INPUT = 0x00FF;
    private const uint WM_INPUT_DEVICE_CHANGE = 0x00FE;
    private const uint WM_CLOSE = 0x0010;
    private const uint WM_DESTROY = 0x0002;
    private const uint GIDC_ARRIVAL = 1;
    private const uint RIM_TYPEHID = 2;
    private const uint RID_INPUT = 0x10000003;
    private const uint RIDI_DEVICENAME = 0x20000007;
    private const uint RIDI_DEVICEINFO = 0x2000000B;
    private const uint RIDEV_PAGEONLY = 0x00000020;
    private const uint RIDEV_INPUTSINK = 0x00000100;
    private const uint RIDEV_DEVNOTIFY = 0x00002000;

    private static readonly NativeMethods.WindowProcedure WindowProcedure = StaticWindowProcedure;
    private static RawInputProbe? current;

    private readonly ProbeOptions options;
    private readonly ACK05ReportDecoder decoder = new();
    private readonly Dictionary<nint, DeviceDescriptor> devices = [];
    private nint window;
    private bool disposed;

    public RawInputProbe(ProbeOptions options)
    {
        this.options = options;
    }

    public void Run()
    {
        current = this;
        CreateMessageWindow();
        RegisterRawInput();
        EnumerateDevices();

        Console.CancelKeyPress += Cancel;
        try
        {
            while (NativeMethods.GetMessage(out var message, nint.Zero, 0, 0) > 0)
            {
                NativeMethods.TranslateMessage(in message);
                NativeMethods.DispatchMessage(in message);
            }
        }
        finally
        {
            Console.CancelKeyPress -= Cancel;
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        if (window != nint.Zero)
        {
            NativeMethods.DestroyWindow(window);
            window = nint.Zero;
        }

        if (ReferenceEquals(current, this))
        {
            current = null;
        }
    }

    private void Cancel(object? sender, ConsoleCancelEventArgs eventArgs)
    {
        eventArgs.Cancel = true;
        NativeMethods.PostMessage(window, WM_CLOSE, nint.Zero, nint.Zero);
    }

    private void CreateMessageWindow()
    {
        var module = NativeMethods.GetModuleHandle(null);
        var className = $"OverCUE.RawInputProbe.{Environment.ProcessId}";
        var windowClass = new NativeMethods.WNDCLASSEX
        {
            Size = (uint)Marshal.SizeOf<NativeMethods.WNDCLASSEX>(),
            Instance = module,
            WindowProcedure = WindowProcedure,
            ClassName = className,
        };

        if (NativeMethods.RegisterClassEx(in windowClass) == 0)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not register the Probe window class.");
        }

        window = NativeMethods.CreateWindowEx(
            0,
            className,
            "OverCUE Raw Input Probe",
            0,
            0,
            0,
            0,
            0,
            new nint(-3),
            nint.Zero,
            module,
            nint.Zero);
        if (window == nint.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not create the Probe message window.");
        }
    }

    private void RegisterRawInput()
    {
        var flags = RIDEV_PAGEONLY | RIDEV_INPUTSINK | RIDEV_DEVNOTIFY;
        var registrations = new[]
        {
            new NativeMethods.RAWINPUTDEVICE(0x01, 0, flags, window),
            new NativeMethods.RAWINPUTDEVICE(0x0C, 0, flags, window),
        };

        if (!NativeMethods.RegisterRawInputDevices(
                registrations,
                (uint)registrations.Length,
                (uint)Marshal.SizeOf<NativeMethods.RAWINPUTDEVICE>()))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not register for Raw Input.");
        }
    }

    private void EnumerateDevices()
    {
        uint count = 0;
        var itemSize = (uint)Marshal.SizeOf<NativeMethods.RAWINPUTDEVICELIST>();
        if (NativeMethods.GetRawInputDeviceList(null, ref count, itemSize) == uint.MaxValue)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not count Raw Input devices.");
        }

        var list = new NativeMethods.RAWINPUTDEVICELIST[checked((int)count)];
        if (count > 0 && NativeMethods.GetRawInputDeviceList(list, ref count, itemSize) == uint.MaxValue)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not enumerate Raw Input devices.");
        }

        foreach (var item in list.Take((int)count).Where(item => item.Type == RIM_TYPEHID))
        {
            var descriptor = Describe(item.Device);
            devices[item.Device] = descriptor;
            if (ShouldPrint(descriptor))
            {
                WriteDevice("present", descriptor);
            }
        }
    }

    private nint WindowMessage(nint messageWindow, uint message, nint wParam, nint lParam)
    {
        switch (message)
        {
            case WM_INPUT:
                ProcessInput(lParam);
                break;
            case WM_INPUT_DEVICE_CHANGE:
                ProcessDeviceChange((uint)wParam, lParam);
                return nint.Zero;
            case WM_CLOSE:
                NativeMethods.DestroyWindow(messageWindow);
                return nint.Zero;
            case WM_DESTROY:
                window = nint.Zero;
                NativeMethods.PostQuitMessage(0);
                return nint.Zero;
        }

        return NativeMethods.DefWindowProc(messageWindow, message, wParam, lParam);
    }

    private void ProcessDeviceChange(uint change, nint device)
    {
        var descriptor = change == GIDC_ARRIVAL
            ? Describe(device)
            : devices.GetValueOrDefault(device) ?? new DeviceDescriptor(device, "unknown", 0, 0, 0, 0);
        if (change == GIDC_ARRIVAL)
        {
            devices[device] = descriptor;
        }

        if (ShouldPrint(descriptor))
        {
            WriteDevice(change == GIDC_ARRIVAL ? "arrival" : "removal", descriptor);
        }

        if (change != GIDC_ARRIVAL)
        {
            devices.Remove(device);
        }
    }

    private void ProcessInput(nint rawInput)
    {
        uint size = 0;
        var headerSize = (uint)Marshal.SizeOf<NativeMethods.RAWINPUTHEADER>();
        if (NativeMethods.GetRawInputData(rawInput, RID_INPUT, nint.Zero, ref size, headerSize) == uint.MaxValue
            || size < headerSize + 8)
        {
            return;
        }

        var buffer = Marshal.AllocHGlobal((int)size);
        try
        {
            if (NativeMethods.GetRawInputData(rawInput, RID_INPUT, buffer, ref size, headerSize) == uint.MaxValue)
            {
                return;
            }

            var header = Marshal.PtrToStructure<NativeMethods.RAWINPUTHEADER>(buffer);
            if (header.Type != RIM_TYPEHID)
            {
                return;
            }

            var descriptor = devices.GetValueOrDefault(header.Device) ?? Describe(header.Device);
            devices[header.Device] = descriptor;
            if (!ShouldPrint(descriptor))
            {
                return;
            }

            var hidOffset = checked((int)headerSize);
            var reportSize = checked((uint)Marshal.ReadInt32(buffer, hidOffset));
            var reportCount = checked((uint)Marshal.ReadInt32(buffer, hidOffset + 4));
            if (reportSize == 0 || reportCount == 0 || reportSize * reportCount > size - headerSize - 8)
            {
                return;
            }

            var reportsOffset = hidOffset + 8;
            for (var index = 0U; index < reportCount; index++)
            {
                var report = new byte[checked((int)reportSize)];
                Marshal.Copy(buffer + reportsOffset + checked((int)(index * reportSize)), report, 0, report.Length);
                WriteReport(descriptor, report, index, reportCount);
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private DeviceDescriptor Describe(nint device)
    {
        var name = ReadDeviceName(device);
        var nativeInfo = new NativeMethods.RID_DEVICE_INFO
        {
            Size = (uint)Marshal.SizeOf<NativeMethods.RID_DEVICE_INFO>(),
        };
        var infoSize = nativeInfo.Size;
        var pointer = Marshal.AllocHGlobal((int)infoSize);
        try
        {
            Marshal.StructureToPtr(nativeInfo, pointer, false);
            var result = NativeMethods.GetRawInputDeviceInfo(device, RIDI_DEVICEINFO, pointer, ref infoSize);
            if (result == uint.MaxValue)
            {
                return new DeviceDescriptor(device, name, 0, 0, 0, 0);
            }

            nativeInfo = Marshal.PtrToStructure<NativeMethods.RID_DEVICE_INFO>(pointer);
            return new DeviceDescriptor(
                device,
                name,
                nativeInfo.Hid.VendorID,
                nativeInfo.Hid.ProductID,
                nativeInfo.Hid.UsagePage,
                nativeInfo.Hid.Usage);
        }
        finally
        {
            Marshal.FreeHGlobal(pointer);
        }
    }

    private static string ReadDeviceName(nint device)
    {
        uint characterCount = 0;
        if (NativeMethods.GetRawInputDeviceInfo(device, RIDI_DEVICENAME, nint.Zero, ref characterCount) == uint.MaxValue
            || characterCount == 0)
        {
            return "unknown";
        }

        var buffer = Marshal.AllocHGlobal(checked((int)((characterCount + 1) * sizeof(char))));
        try
        {
            if (NativeMethods.GetRawInputDeviceInfo(device, RIDI_DEVICENAME, buffer, ref characterCount) == uint.MaxValue)
            {
                return "unknown";
            }

            return Marshal.PtrToStringUni(buffer, (int)characterCount)?.TrimEnd('\0') ?? "unknown";
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private bool ShouldPrint(DeviceDescriptor descriptor) =>
        options.AllHid
        || (descriptor.VendorID == VendorID && descriptor.ProductID == ProductID)
        || (descriptor.Name.Contains("VID_28BD", StringComparison.OrdinalIgnoreCase)
            && descriptor.Name.Contains("PID_0202", StringComparison.OrdinalIgnoreCase));

    private void WriteDevice(string state, DeviceDescriptor descriptor)
    {
        if (options.JsonLines)
        {
            WriteJson(new
            {
                type = "device",
                timestamp = DateTimeOffset.UtcNow,
                state,
                descriptor.Name,
                vendorID = $"{descriptor.VendorID:X4}",
                productID = $"{descriptor.ProductID:X4}",
                usagePage = $"{descriptor.UsagePage:X4}",
                usage = $"{descriptor.Usage:X4}",
            });
            return;
        }

        Console.WriteLine(
            $"device {state}: VID={descriptor.VendorID:X4} PID={descriptor.ProductID:X4} "
            + $"usage={descriptor.UsagePage:X4}/{descriptor.Usage:X4} path={descriptor.Name}");
    }

    private void WriteReport(DeviceDescriptor descriptor, byte[] report, uint index, uint count)
    {
        var decoded = report.Length == ACK05ReportDecoder.ReportLength
            ? Format(decoder.Decode(report[0], report))
            : null;
        var pressed = report.Length == ACK05ReportDecoder.ReportLength
            ? decoder.PressedKeys(report[0], report)?.Select(key => key.ToString()).Order().ToArray()
            : null;

        if (options.JsonLines)
        {
            WriteJson(new
            {
                type = "report",
                timestamp = DateTimeOffset.UtcNow,
                descriptor.Name,
                vendorID = $"{descriptor.VendorID:X4}",
                productID = $"{descriptor.ProductID:X4}",
                usagePage = $"{descriptor.UsagePage:X4}",
                usage = $"{descriptor.Usage:X4}",
                index,
                count,
                reportID = report.Length > 0 ? report[0] : 0,
                bytes = Convert.ToHexString(report),
                decoded,
                pressed,
            });
            return;
        }

        Console.WriteLine(
            $"{DateTimeOffset.Now:HH:mm:ss.fff} {Convert.ToHexString(report)}"
            + (decoded is null ? string.Empty : $"  {decoded}")
            + (pressed is null ? string.Empty : $"  pressed=[{string.Join(",", pressed)}]"));
    }

    private static string? Format(ACK05Event? value) => value switch
    {
        ACK05Event.Dial { Direction: DialDirection.Clockwise } => "dial:clockwise",
        ACK05Event.Dial { Direction: DialDirection.Counterclockwise } => "dial:counterclockwise",
        ACK05Event.KeyDown keyDown => $"keyDown:{keyDown.Key}",
        ACK05Event.AllReleased => "allReleased",
        _ => null,
    };

    private static void WriteJson<T>(T value) => Console.WriteLine(JsonSerializer.Serialize(value));

    private static nint StaticWindowProcedure(nint window, uint message, nint wParam, nint lParam) =>
        current?.WindowMessage(window, message, wParam, lParam)
        ?? NativeMethods.DefWindowProc(window, message, wParam, lParam);

    private sealed record DeviceDescriptor(
        nint Handle,
        string Name,
        uint VendorID,
        uint ProductID,
        ushort UsagePage,
        ushort Usage);
}

internal static partial class NativeMethods
{
    internal delegate nint WindowProcedure(nint window, uint message, nint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct WNDCLASSEX
    {
        internal uint Size;
        internal uint Style;
        [MarshalAs(UnmanagedType.FunctionPtr)]
        internal WindowProcedure? WindowProcedure;
        internal int ClassExtraBytes;
        internal int WindowExtraBytes;
        internal nint Instance;
        internal nint Icon;
        internal nint Cursor;
        internal nint BackgroundBrush;
        internal string? MenuName;
        internal string ClassName;
        internal nint SmallIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct RAWINPUTDEVICE
    {
        internal ushort UsagePage;
        internal ushort Usage;
        internal uint Flags;
        internal nint Target;

        internal RAWINPUTDEVICE(ushort usagePage, ushort usage, uint flags, nint target)
        {
            UsagePage = usagePage;
            Usage = usage;
            Flags = flags;
            Target = target;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct RAWINPUTDEVICELIST
    {
        internal nint Device;
        internal uint Type;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct RAWINPUTHEADER
    {
        internal uint Type;
        internal uint Size;
        internal nint Device;
        internal nint WParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct RID_DEVICE_INFO
    {
        internal uint Size;
        internal uint Type;
        internal RID_DEVICE_INFO_UNION Union;

        internal readonly RID_DEVICE_INFO_HID Hid => Union.Hid;
    }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    internal struct RID_DEVICE_INFO_UNION
    {
        [FieldOffset(0)]
        internal RID_DEVICE_INFO_HID Hid;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct RID_DEVICE_INFO_HID
    {
        internal uint VendorID;
        internal uint ProductID;
        internal uint VersionNumber;
        internal ushort UsagePage;
        internal ushort Usage;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct POINT
    {
        internal int X;
        internal int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MSG
    {
        internal nint Window;
        internal uint Message;
        internal nint WParam;
        internal nint LParam;
        internal uint Time;
        internal POINT Point;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern nint GetModuleHandle(string? moduleName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern ushort RegisterClassEx(in WNDCLASSEX windowClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern nint CreateWindowEx(
        uint extendedStyle,
        string className,
        string windowName,
        uint style,
        int x,
        int y,
        int width,
        int height,
        nint parent,
        nint menu,
        nint instance,
        nint parameter);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DestroyWindow(nint window);

    [DllImport("user32.dll")]
    internal static extern nint DefWindowProc(nint window, uint message, nint wParam, nint lParam);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool PostMessage(nint window, uint message, nint wParam, nint lParam);

    [DllImport("user32.dll")]
    internal static extern void PostQuitMessage(int exitCode);

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern int GetMessage(out MSG message, nint window, uint minimumMessage, uint maximumMessage);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool TranslateMessage(in MSG message);

    [DllImport("user32.dll")]
    internal static extern nint DispatchMessage(in MSG message);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool RegisterRawInputDevices(
        [In] RAWINPUTDEVICE[] devices,
        uint deviceCount,
        uint deviceSize);

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern uint GetRawInputDeviceList(
        [Out] RAWINPUTDEVICELIST[]? devices,
        ref uint deviceCount,
        uint deviceSize);

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern uint GetRawInputData(
        nint rawInput,
        uint command,
        nint data,
        ref uint size,
        uint headerSize);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern uint GetRawInputDeviceInfo(
        nint device,
        uint command,
        nint data,
        ref uint size);
}
