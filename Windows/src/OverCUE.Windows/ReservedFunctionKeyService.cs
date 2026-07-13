using System.ComponentModel;
using System.Runtime.InteropServices;
using OverCUE.Core;

namespace OverCUE.Windows;

internal sealed class ReservedFunctionKeyService : IDisposable
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;
    private const uint F13 = 0x7C;
    private const uint F24 = 0x87;

    private readonly HookProcedure hookProcedure;
    private readonly object sync = new();
    private readonly HashSet<ACK05Key> pressedKeys = [];
    private nint hook;

    public event Action<ACK05Event>? InputDecoded;
    public event Action<IReadOnlySet<ACK05Key>>? PressedKeysChanged;

    public ReservedFunctionKeyService() => hookProcedure = ProcessKeyboard;

    public void Attach()
    {
        if (hook != nint.Zero) return;
        hook = SetWindowsHookEx(WH_KEYBOARD_LL, hookProcedure, GetModuleHandle(null), 0);
        if (hook == nint.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not monitor XP-Pen reserved function keys.");
    }

    public void Dispose()
    {
        if (hook != nint.Zero) UnhookWindowsHookEx(hook);
        hook = nint.Zero;
        lock (sync) pressedKeys.Clear();
    }

    public bool ProcessForegroundKey(uint virtualKey, bool isDown)
    {
        if (virtualKey is < F13 or > F24) return false;
        ProcessReservedKey(virtualKey, isDown);
        return true;
    }

    private nint ProcessKeyboard(int code, nint message, nint data)
    {
        if (code < 0) return CallNextHookEx(hook, code, message, data);
        var input = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(data);
        if (input.VirtualKey is < F13 or > F24) return CallNextHookEx(hook, code, message, data);

        var isDown = message is WM_KEYDOWN or WM_SYSKEYDOWN;
        var isUp = message is WM_KEYUP or WM_SYSKEYUP;
        if (!isDown && !isUp) return 1;

        ProcessReservedKey(input.VirtualKey, isDown);

        // F13-F24 are reserved exclusively for the XP-Pen bridge and must not leak to rekordbox.
        return 1;
    }

    private void ProcessReservedKey(uint virtualKey, bool isDown)
    {
        ACK05Event? decoded = null;
        IReadOnlySet<ACK05Key>? snapshot = null;
        if (virtualKey <= 0x85)
        {
            var key = (ACK05Key)(virtualKey - F13);
            lock (sync)
            {
                if (isDown && pressedKeys.Add(key))
                {
                    decoded = new ACK05Event.KeyDown(key);
                    snapshot = pressedKeys.ToHashSet();
                }
                else if (!isDown && pressedKeys.Remove(key))
                    snapshot = pressedKeys.ToHashSet();
            }
        }
        else if (isDown)
        {
            decoded = new ACK05Event.Dial(
                virtualKey == 0x86 ? DialDirection.Counterclockwise : DialDirection.Clockwise);
        }
        if (decoded is not null) InputDecoded?.Invoke(decoded);
        if (snapshot is not null) PressedKeysChanged?.Invoke(snapshot);
    }

    private delegate nint HookProcedure(int code, nint message, nint data);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct KBDLLHOOKSTRUCT
    {
        public readonly uint VirtualKey;
        public readonly uint ScanCode;
        public readonly uint Flags;
        public readonly uint Time;
        public readonly UIntPtr ExtraInformation;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWindowsHookEx(int hookID, HookProcedure procedure, nint module, uint threadID);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(nint hook);
    [DllImport("user32.dll")]
    private static extern nint CallNextHookEx(nint hook, int code, nint message, nint data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern nint GetModuleHandle(string? moduleName);
}
