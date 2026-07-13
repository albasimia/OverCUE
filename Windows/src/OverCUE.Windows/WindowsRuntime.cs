using System.Diagnostics;
using System.Collections.Concurrent;
using System.IO;
using System.Runtime.InteropServices;
using System.Xml.Linq;
using OverCUE.Core;

namespace OverCUE.Windows;

internal sealed record WindowsShortcut(ushort VirtualKey, KeyModifiers Modifiers);
[Flags] internal enum KeyModifiers { None = 0, Shift = 1, Control = 2, Alt = 4 }

internal enum RekordboxShortcutCategory
{
    Browse, Deck1, Deck2, AllDecks, Sampler, Recordings, General, View, Playlist, Other,
}

internal sealed record RekordboxShortcutEntry(
    int Index,
    string CommandID,
    string Description,
    string Shortcut,
    RekordboxShortcutCategory Category);

internal sealed class RekordboxShortcutCatalog
{
    private readonly Dictionary<string, WindowsShortcut> shortcuts = new(StringComparer.OrdinalIgnoreCase);
    public string MappingName { get; private set; } = AppLocalization.Current.Text("mapping.notDetected");

    public string MappingPath { get; private set; } = string.Empty;
    public IReadOnlyList<RekordboxShortcutEntry> Entries { get; private set; } = [];

    public static RekordboxShortcutCatalog Load(string mode)
    {
        var baseDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Pioneer", "rekordbox6");
        return Load(mode, baseDirectory);
    }

    internal static RekordboxShortcutCatalog Load(string mode, string baseDirectory)
    {
        var result = new RekordboxShortcutCatalog();
        var directory = Path.Combine(baseDirectory, "KeyMappings");
        if (!Directory.Exists(directory)) return result;

        var mappings = Directory.EnumerateFiles(directory, "rekordbox_*.mappings")
            .OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase)
            .Select(path =>
            {
                try
                {
                    var document = XDocument.Load(path);
                    var name = document.Descendants("VALUE")
                        .FirstOrDefault(node => node.Attribute("name")?.Value == "keyMappingName")
                        ?.Attribute("val")?.Value ?? Path.GetFileNameWithoutExtension(path);
                    var id = Path.GetFileNameWithoutExtension(path).Split('_').Last();
                    return new MappingFile(id, name, path, document);
                }
                catch { return null; }
            })
            .Where(value => value is not null)
            .Cast<MappingFile>()
            .ToArray();

        var selectedID = ReadSelectedMappingID(baseDirectory, mode);
        var selected = selectedID is null ? null
            : mappings.FirstOrDefault(value => value.ID.Equals(selectedID, StringComparison.OrdinalIgnoreCase));
        if (selected is null || !selected.HasAssignedShortcuts)
            selected = OriginalMapping(mode, mappings) ?? selected;
        if (selected is null) return result;

        result.MappingName = selected.Name;
        result.MappingPath = selected.Path;
        var entries = new List<RekordboxShortcutEntry>();
        foreach (var node in selected.Document.Descendants("MAPPING"))
        {
            var id = node.Attribute("commandId")?.Value;
            var raw = node.Attribute("key")?.Value;
            if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(raw)) continue;
            var description = node.Attribute("description")?.Value?.Trim();
            entries.Add(new(entries.Count, id, string.IsNullOrWhiteSpace(description) ? id : description,
                raw.Trim(), CategoryFor(id)));
            if (Parse(raw) is { } shortcut) result.shortcuts[id] = shortcut;
        }
        result.Entries = entries;
        return result;
    }

    private static MappingFile? OriginalMapping(string mode, IReadOnlyList<MappingFile> mappings)
    {
        var performance = mode.Equals("performance", StringComparison.OrdinalIgnoreCase);
        var originalID = performance ? "0000000000000" : "0000000000030";
        var originalName = performance ? "Performance 1 (Preset)" : "Export (Preset)";
        return mappings.FirstOrDefault(value => value.ID.Equals(originalID, StringComparison.OrdinalIgnoreCase))
            ?? mappings.FirstOrDefault(value => value.Name.Equals(originalName, StringComparison.OrdinalIgnoreCase))
            ?? mappings
                .Where(value => value.Name.Contains(performance ? "performance" : "export",
                    StringComparison.OrdinalIgnoreCase))
                .OrderBy(value => value.Path, StringComparer.OrdinalIgnoreCase)
                .FirstOrDefault();
    }
    public WindowsShortcut? Find(string commandID) => shortcuts.GetValueOrDefault(commandID);

    private static RekordboxShortcutCategory CategoryFor(string commandID)
    {
        var value = commandID.ToLowerInvariant();
        if (value is "3000" or "3001" or "3002") return RekordboxShortcutCategory.AllDecks;
        if (value.StartsWith("30")) return RekordboxShortcutCategory.Deck1;
        if (value.StartsWith("31")) return RekordboxShortcutCategory.Deck2;
        if (value.StartsWith('f')) return RekordboxShortcutCategory.Sampler;
        return value switch
        {
            "d0f0" => RekordboxShortcutCategory.Recordings,
            "7000" or "7003" => RekordboxShortcutCategory.General,
            "b04d" => RekordboxShortcutCategory.View,
            "500a" => RekordboxShortcutCategory.Playlist,
            _ when value.StartsWith('b') => RekordboxShortcutCategory.Browse,
            _ => RekordboxShortcutCategory.Other,
        };
    }

    private static WindowsShortcut? Parse(string raw)
    {
        var parts = raw.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        var modifiers = KeyModifiers.None;
        foreach (var part in parts.Take(parts.Length - 1)) modifiers |= part.ToLowerInvariant() switch
        {
            "shift" => KeyModifiers.Shift,
            "ctrl" or "control" or "command" => KeyModifiers.Control,
            "alt" or "option" => KeyModifiers.Alt,
            _ => KeyModifiers.None
        };
        var key = parts.LastOrDefault()?.Trim().ToUpperInvariant();
        ushort vk = key switch
        {
            "SPACE" or "SPACEBAR" => 0x20,
            "LEFT" or "CURSOR LEFT" => 0x25,
            "UP" or "CURSOR UP" => 0x26,
            "RIGHT" or "CURSOR RIGHT" => 0x27,
            "DOWN" or "CURSOR DOWN" => 0x28,
            "BACKSPACE" or "DELETE" => 0x08,
            "ENTER" or "RETURN" => 0x0D,
            "ESC" or "ESCAPE" => 0x1B,
            _ when key?.Length == 1 => key[0],
            _ when key is not null && key.StartsWith('F') && int.TryParse(key[1..], out var number) && number is >= 1 and <= 24
                => (ushort)(0x70 + number - 1),
            _ => 0,
        };
        return vk == 0 ? null : new(vk, modifiers);
    }

    private static string? ReadSelectedMappingID(string baseDirectory, string mode)
    {
        var settingsPath = Path.Combine(baseDirectory, "rekordbox3.settings");
        if (!File.Exists(settingsPath))
            settingsPath = Directory.EnumerateFiles(baseDirectory, "*.settings")
                .Where(path => !Path.GetFileName(path).Contains("backup", StringComparison.OrdinalIgnoreCase))
                .OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase)
                .FirstOrDefault() ?? string.Empty;
        if (!File.Exists(settingsPath)) return null;
        try
        {
            var target = mode.Equals("performance", StringComparison.OrdinalIgnoreCase) ? "perform" : "export";
            return XDocument.Load(settingsPath).Descendants("VALUE")
                .FirstOrDefault(node =>
                    node.Attribute("name")?.Value.Contains(target, StringComparison.OrdinalIgnoreCase) == true
                    && node.Attribute("name")?.Value.Contains("keymapping", StringComparison.OrdinalIgnoreCase) == true)
                ?.Attribute("val")?.Value;
        }
        catch { return null; }
    }

    private sealed record MappingFile(string ID, string Name, string Path, XDocument Document)
    {
        public bool HasAssignedShortcuts => Document.Descendants("MAPPING").Any(node =>
            !string.IsNullOrWhiteSpace(node.Attribute("commandId")?.Value)
            && !string.IsNullOrWhiteSpace(node.Attribute("key")?.Value));
    }
}

internal sealed class WindowsActionRuntime : IDisposable
{
    private readonly OverCUEConfiguration configuration;
    private readonly string configPath;
    private readonly InputActionResolver resolver = new();
    private readonly AcceleratingKeyRepeatProfile repeatProfile = new();
    private readonly WaveformDragProfile dragProfile = new();
    private readonly BlockingCollection<ShortcutRequest> shortcutQueue = new();
    private readonly Dictionary<ushort, int> heldModifierCounts = [];
    private readonly HashSet<ushort> heldShortcutKeys = [];
    private readonly Thread shortcutThread;
    private RekordboxShortcutCatalog shortcuts;
    private ActionMapping mapping;
    private int group = 1;
    private System.Threading.Timer? repeatTimer, dragReleaseTimer;
    private ACK05Key? repeatingKey;
    private long repeatStarted;
    private POINT? originalPointer, dragPosition;
    private double? smoothedInterval;
    private long lastDialTimestamp;
    private DialDirection? lastDirection;

    public event Action<int, string>? RuntimeChanged;
    public event Action<string>? StatusChanged;

    public WindowsActionRuntime(OverCUEConfiguration configuration, string configPath)
    {
        this.configuration = configuration; this.configPath = configPath;
        mapping = CurrentGroup().ToActionMapping();
        shortcuts = RekordboxShortcutCatalog.Load(CurrentGroup().RekordboxMode);
        shortcutThread = new(ProcessShortcutQueue) { IsBackground = true, Name = "OverCUE shortcut output" };
        shortcutThread.Start();
    }

    public void SetGroup(int value)
    {
        if (value is < 1 or > 4) return;
        foreach (var action in resolver.Reset(mapping)) Route(action);
        StopRepeat(); group = value; mapping = CurrentGroup().ToActionMapping();
        shortcuts = RekordboxShortcutCatalog.Load(CurrentGroup().RekordboxMode);
        RuntimeChanged?.Invoke(group, CurrentGroup().RekordboxMode);
    }

    public void SetMode(string mode)
    {
        CurrentGroup().RekordboxMode = mode; configuration.Save(configPath);
        shortcuts = RekordboxShortcutCatalog.Load(mode);
        RuntimeChanged?.Invoke(group, mode);
    }

    public void ProcessPressedKeys(IReadOnlySet<ACK05Key> keys)
    {
        var released = resolver.PressedKeys.Except(keys).ToHashSet();
        foreach (var action in resolver.Handle(keys, mapping))
        {
            Route(action);
            if (action.Phase == ActionPhase.Pressed && action.Target.Behavior == ActionBehavior.AcceleratingRepeat
                && action.SourceKey is { } key) StartRepeat(key);
        }
        if (repeatingKey is { } repeated && released.Contains(repeated)) StopRepeat();
    }

    public void ProcessDial(DialDirection direction)
    {
        Route(resolver.DialEvent(direction, mapping) ?? new(
            mapping.Dial.GetValueOrDefault(direction) ?? ActionTarget.ForAction(
                direction == DialDirection.Clockwise ? ActionID.JogSearchRight : ActionID.JogSearchLeft),
            ActionPhase.Triggered, null, direction.ToString()));
    }

    public void Dispose() { StopRepeat(); FinishDrag(true); shortcutQueue.CompleteAdding(); }

    private OverCUEGroupMapping CurrentGroup() => configuration.Profiles[configuration.DefaultProfile].Mapping(group);

    private void Route(ActionEvent value)
    {
        if (value.Target.Action is { } internalAction && internalAction.Behavior() == ActionBehavior.InternalCommand)
        {
            if (value.Phase is not (ActionPhase.Triggered or ActionPhase.Repeated)) return;
            switch (internalAction)
            {
                case ActionID.CaptureWaveformPosition: CaptureWaveform(); break;
                case ActionID.JogSearchLeft: Drag(DialDirection.Counterclockwise); break;
                case ActionID.JogSearchRight: Drag(DialDirection.Clockwise); break;
                case ActionID.CycleGroup: SetGroup(group % 4 + 1); break;
                case ActionID.CycleGroupBackward: SetGroup((group + 2) % 4 + 1); break;
                case ActionID.ToggleRekordboxMode: SetMode(CurrentGroup().RekordboxMode == "performance" ? "export" : "performance"); break;
            }
            return;
        }
        var command = RekordboxActionAdapter.CommandID(value.Target);
        var shortcut = command is null ? null : shortcuts.Find(command);
        if (shortcut is null)
        {
            StatusChanged?.Invoke(AppLocalization.Current.Text(
                "common.unassigned") + $": {command ?? value.Target.Action?.ConfigurationValue()} ({shortcuts.MappingName})");
            return;
        }
        if (!IsRekordboxFrontmost())
        {
            StatusChanged?.Invoke(AppLocalization.Current.Text("message.rekordboxNotFrontmost"));
            return;
        }
        var cueHandoff = ExportHeldCueForPlay(value, command!);
        if (cueHandoff is not null)
            QueueCuePlayHandoff(cueHandoff, shortcut, command!);
        else if (value.Phase is ActionPhase.Triggered or ActionPhase.Repeated)
            QueueShortcut(shortcut, true, true, command!);
        else if (value.Phase == ActionPhase.Pressed)
        {
            QueueShortcut(shortcut, true, value.Target.Behavior != ActionBehavior.Hold, command!);
        }
        else if (value.Phase == ActionPhase.Released)
            QueueShortcut(shortcut, false, false, command!);
        else return;
        StatusChanged?.Invoke(AppLocalization.Current.Text(
            "message.send", command!, shortcut.VirtualKey.ToString("X2")));
    }

    private void StartRepeat(ACK05Key key)
    {
        StopRepeat(); repeatingKey = key; repeatStarted = Stopwatch.GetTimestamp();
        repeatTimer = new(_ => Repeat(), null, (int)repeatProfile.InitialDelayMilliseconds, Timeout.Infinite);
    }
    private void Repeat()
    {
        if (repeatingKey is not { } key || resolver.RepeatedEvent(key, mapping) is not { } value) { StopRepeat(); return; }
        Route(value); var held = Stopwatch.GetElapsedTime(repeatStarted).TotalMilliseconds;
        repeatTimer?.Change((int)repeatProfile.RepeatInterval(held), Timeout.Infinite);
    }
    private void StopRepeat() { repeatTimer?.Dispose(); repeatTimer = null; repeatingKey = null; }

    private void CaptureWaveform()
    {
        if (!GetCursorPos(out var point)) return;
        CurrentGroup().WaveformPosition = new(point.X, point.Y); configuration.Save(configPath);
        StatusChanged?.Invoke(AppLocalization.Current.Text("message.waveformSaved", point.X, point.Y));
    }
    private void Drag(DialDirection direction)
    {
        if (!IsRekordboxFrontmost() || CurrentGroup().WaveformPosition is not { } anchor) { FinishDrag(true); return; }
        if (dragPosition is null)
        {
            GetCursorPos(out var original); originalPointer = original; dragPosition = new((int)anchor.X, (int)anchor.Y);
            SetCursorPos(dragPosition.Value.X, dragPosition.Value.Y); MouseEvent(0x0002);
        }
        var now = Stopwatch.GetTimestamp(); double? raw = lastDialTimestamp == 0 ? null : Stopwatch.GetElapsedTime(lastDialTimestamp, now).TotalMilliseconds;
        var effective = lastDirection == direction && raw is not null ? dragProfile.SmoothedInterval(smoothedInterval, raw.Value) : (double?)null;
        smoothedInterval = effective; lastDirection = direction; lastDialTimestamp = now;
        var position = dragPosition.Value; position.X += (int)Math.Round(dragProfile.HorizontalDelta(direction, effective)); dragPosition = position;
        SetCursorPos(position.X, position.Y); MouseEvent(0x0001);
        dragReleaseTimer?.Dispose(); dragReleaseTimer = new(_ => FinishDrag(true), null, 150, Timeout.Infinite);
    }
    private void FinishDrag(bool restore)
    {
        dragReleaseTimer?.Dispose(); dragReleaseTimer = null;
        if (dragPosition is not null) MouseEvent(0x0004);
        if (restore && originalPointer is { } original) SetCursorPos(original.X, original.Y);
        originalPointer = null; dragPosition = null; lastDialTimestamp = 0; lastDirection = null; smoothedInterval = null;
    }

    private static bool IsRekordboxFrontmost()
    {
        var window = GetForegroundWindow(); GetWindowThreadProcessId(window, out var pid);
        try { return Process.GetProcessById((int)pid).ProcessName.Contains("rekordbox", StringComparison.OrdinalIgnoreCase); }
        catch { return false; }
    }
    private void QueueShortcut(WindowsShortcut shortcut, bool down, bool tap, string command)
    {
        try { shortcutQueue.Add(new(shortcut, down, tap, command)); }
        catch (InvalidOperationException) { }
    }

    private void QueueCuePlayHandoff(WindowsShortcut cue, WindowsShortcut play, string command)
    {
        try { shortcutQueue.Add(new(play, true, true, command, cue)); }
        catch (InvalidOperationException) { }
    }

    private WindowsShortcut? ExportHeldCueForPlay(ActionEvent value, string command)
    {
        if (!command.Equals("3006", StringComparison.OrdinalIgnoreCase)
            || value.Phase != ActionPhase.Triggered
            || !CurrentGroup().RekordboxMode.Equals("export", StringComparison.OrdinalIgnoreCase)) return null;

        // Resolve the held Cue from the active mapping, never from a fixed ACK05 key.
        return mapping.HasCommand(resolver.PressedKeys, "3007") ? shortcuts.Find("3007") : null;
    }

    private void ProcessShortcutQueue()
    {
        foreach (var request in shortcutQueue.GetConsumingEnumerable())
        {
            var sent = request.CueHandoff is { } cue
                ? SendCuePlayHandoff(cue, request.Shortcut)
                : SendShortcut(request.Shortcut, request.Down, request.Tap);
            StatusChanged?.Invoke(sent
                ? AppLocalization.Current.Text(
                    "message.send", request.Command, request.Shortcut.VirtualKey.ToString("X2"))
                : AppLocalization.Current.Text(
                    "message.sendFailed", request.Command, Marshal.GetLastWin32Error()));
        }
        ReleaseHeldShortcutState();
    }

    private bool SendShortcut(WindowsShortcut shortcut, bool down, bool tap)
    {
        var mods = new[] { (KeyModifiers.Control, (ushort)0x11), (KeyModifiers.Shift, (ushort)0x10), (KeyModifiers.Alt, (ushort)0x12) };
        var inputs = new List<INPUT>();
        if (down)
            foreach (var (flag, key) in mods)
                if (shortcut.Modifiers.HasFlag(flag)) AcquireModifier(key, inputs);
        inputs.Add(KeyboardInput(shortcut.VirtualKey, !down));
        if (!tap)
        {
            if (down) heldShortcutKeys.Add(shortcut.VirtualKey);
            else heldShortcutKeys.Remove(shortcut.VirtualKey);
            if (!down)
                foreach (var (flag, key) in mods.Reverse())
                    if (shortcut.Modifiers.HasFlag(flag)) ReleaseModifier(key, inputs);
            return SendNativeInput(inputs.ToArray());
        }

        var sent = SendNativeInput(inputs.ToArray());
        Thread.Sleep(24);
        inputs.Clear();
        inputs.Add(KeyboardInput(shortcut.VirtualKey, true));
        foreach (var (flag, key) in mods.Reverse())
            if (shortcut.Modifiers.HasFlag(flag)) ReleaseModifier(key, inputs);
        return SendNativeInput(inputs.ToArray()) && sent;
    }

    private bool SendCuePlayHandoff(WindowsShortcut cue, WindowsShortcut play)
    {
        if (!heldShortcutKeys.Contains(cue.VirtualKey)) return SendShortcut(play, true, true);

        var mods = new[] { (KeyModifiers.Control, (ushort)0x11), (KeyModifiers.Shift, (ushort)0x10), (KeyModifiers.Alt, (ushort)0x12) };
        var inputs = new List<INPUT>();
        foreach (var (flag, key) in mods)
            if (play.Modifiers.HasFlag(flag)) AcquireModifier(key, inputs);
        inputs.Add(KeyboardInput(play.VirtualKey, false));
        var sent = SendNativeInput(inputs.ToArray());

        // Keep Play physically down while Cue is released so rekordbox latches playback
        // at the current preview position instead of returning to the Cue point.
        Thread.Sleep(32);
        inputs.Clear();
        inputs.Add(KeyboardInput(cue.VirtualKey, true));
        heldShortcutKeys.Remove(cue.VirtualKey);
        foreach (var (flag, key) in mods.Reverse())
            if (cue.Modifiers.HasFlag(flag)) ReleaseModifier(key, inputs);
        sent = SendNativeInput(inputs.ToArray()) && sent;

        Thread.Sleep(32);
        inputs.Clear();
        inputs.Add(KeyboardInput(play.VirtualKey, true));
        foreach (var (flag, key) in mods.Reverse())
            if (play.Modifiers.HasFlag(flag)) ReleaseModifier(key, inputs);
        return SendNativeInput(inputs.ToArray()) && sent;
    }

    private void AcquireModifier(ushort key, List<INPUT> inputs)
    {
        var count = heldModifierCounts.GetValueOrDefault(key);
        heldModifierCounts[key] = count + 1;
        if (count == 0) inputs.Add(KeyboardInput(key, false));
    }

    private void ReleaseModifier(ushort key, List<INPUT> inputs)
    {
        var count = heldModifierCounts.GetValueOrDefault(key);
        if (count <= 1)
        {
            heldModifierCounts.Remove(key);
            if (count == 1) inputs.Add(KeyboardInput(key, true));
        }
        else heldModifierCounts[key] = count - 1;
    }

    private void ReleaseHeldShortcutState()
    {
        var inputs = heldShortcutKeys.Select(key => KeyboardInput(key, true))
            .Concat(heldModifierCounts.Keys.Select(key => KeyboardInput(key, true)))
            .ToArray();
        heldShortcutKeys.Clear();
        heldModifierCounts.Clear();
        if (inputs.Length > 0) SendNativeInput(inputs);
    }
    private static INPUT KeyboardInput(ushort key, bool up) => new()
    {
        Type = 1,
        Union = new INPUTUNION
        {
            Keyboard = new KEYBDINPUT
            {
                Scan = (ushort)MapVirtualKey(key, 0),
                Flags = 0x0008U | (up ? 0x0002U : 0U) | (IsExtendedKey(key) ? 0x0001U : 0U),
            }
        },
    };
    private static bool IsExtendedKey(ushort key) => key is >= 0x21 and <= 0x2E && key is not 0x20;
    private static void MouseEvent(uint flags) => SendNativeInput([new INPUT
    {
        Type = 0,
        Union = new INPUTUNION { Mouse = new MOUSEINPUT { Flags = flags } },
    }]);
    private static bool SendNativeInput(INPUT[] inputs) =>
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>()) == (uint)inputs.Length;

    private sealed record ShortcutRequest(
        WindowsShortcut Shortcut, bool Down, bool Tap, string Command, WindowsShortcut? CueHandoff = null);
    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; public POINT(int x, int y) { X = x; Y = y; } }
    [StructLayout(LayoutKind.Sequential)] private struct INPUT { public uint Type; public INPUTUNION Union; }
    [StructLayout(LayoutKind.Explicit)]
    private struct INPUTUNION
    {
        [FieldOffset(0)] public MOUSEINPUT Mouse;
        [FieldOffset(0)] public KEYBDINPUT Keyboard;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort VirtualKey, Scan;
        public uint Flags, Time;
        public UIntPtr ExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int Dx, Dy;
        public uint MouseData, Flags, Time;
        public UIntPtr ExtraInfo;
    }
    [DllImport("user32.dll")] private static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint window, out uint processId);
    [DllImport("user32.dll", EntryPoint = "MapVirtualKeyW")] private static extern uint MapVirtualKey(uint code, uint mapType);
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint inputCount, INPUT[] inputs, int size);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
}
