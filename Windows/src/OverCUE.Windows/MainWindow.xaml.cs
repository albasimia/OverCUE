using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using System.Text.Json;
using OverCUE.Core;
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;
using Color = System.Windows.Media.Color;
using ComboBox = System.Windows.Controls.ComboBox;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using RadioButton = System.Windows.Controls.RadioButton;

namespace OverCUE.Windows;

public partial class MainWindow : Window
{
    public static readonly DependencyProperty DeviceContentRotationAngleProperty =
        DependencyProperty.Register(
            nameof(DeviceContentRotationAngle),
            typeof(double),
            typeof(MainWindow),
            new PropertyMetadata(0d));

    public double DeviceContentRotationAngle
    {
        get => (double)GetValue(DeviceContentRotationAngleProperty);
        private set => SetValue(DeviceContentRotationAngleProperty, value);
    }

    private readonly string configPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OverCUE", "config.json");
    private readonly string uiStatePath = Environment.GetEnvironmentVariable("OVERCUE_UI_STATE_PATH")
        ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OverCUE", "ui-state.json");
    private readonly OverCUEConfiguration configuration;
    private readonly RawInputService inputService = new();
    private readonly ReservedFunctionKeyService functionKeyService = new();
    private readonly WindowsActionRuntime runtime;
    private readonly Dictionary<ACK05Key, int> highlightVersions = [];
    private readonly HashSet<ACK05Key> previousCaptureKeys = [];
    private readonly List<ACK05Key> capturedKeyOrder = [];
    private readonly HashSet<ACK05Key> selectedDeviceKeys = [];
    private readonly HashSet<DialDirection> selectedDialDirections = [];
    private int dialHighlightVersion;
    private int currentGroup = 1;
    private int rotationQuarterTurns = 1;
    private bool ready;
    private MappingRow? editingRow;
    private string? selectedConfigurationValue;

    public MainWindow()
    {
        InitializeComponent();
        rotationQuarterTurns = LoadDeviceRotation();
        ApplyDeviceRotation();
        configuration = OverCUEConfiguration.Load(configPath);
        runtime = new WindowsActionRuntime(configuration, configPath);
        ready = true;
        ConfigPathText.Text = configPath;
        ShowGroup(1);
        SourceInitialized += (_, _) =>
        {
            inputService.Attach(this);
            functionKeyService.Attach();
        };
        Closed += (_, _) =>
        {
            inputService.Dispose();
            functionKeyService.Dispose();
            runtime.Dispose();
        };
        inputService.ConnectionChanged += connected => Dispatcher.Invoke(() =>
            StatusText.Text = connected ? "ACK05入力待機中" : "ACK05未接続");
        inputService.InputDecoded += value => Dispatcher.Invoke(() => ProcessDecodedInput(value));
        inputService.PressedKeysChanged += keys => Dispatcher.Invoke(() => ProcessPressedKeys(keys));
        functionKeyService.InputDecoded += value => Dispatcher.Invoke(() => ProcessDecodedInput(value));
        functionKeyService.PressedKeysChanged += keys => Dispatcher.Invoke(() => ProcessPressedKeys(keys));
        PreviewKeyDown += (_, args) => ProcessForegroundFunctionKey(args, true);
        PreviewKeyUp += (_, args) => ProcessForegroundFunctionKey(args, false);
        runtime.StatusChanged += text => Dispatcher.BeginInvoke(() => InputText.Text = text);
        runtime.RuntimeChanged += (group, _) => Dispatcher.Invoke(() => ShowGroup(group));
    }

    private void ProcessForegroundFunctionKey(System.Windows.Input.KeyEventArgs args, bool isDown)
    {
        var key = args.Key == Key.System ? args.SystemKey : args.Key;
        if (functionKeyService.ProcessForegroundKey((uint)KeyInterop.VirtualKeyFromKey(key), isDown))
            args.Handled = true;
    }

    private void RotateDeviceClick(object sender, RoutedEventArgs e)
    {
        rotationQuarterTurns = (rotationQuarterTurns + 1) % 4;
        ApplyDeviceRotation();
        SaveDeviceRotation();
    }

    private void ApplyDeviceRotation()
    {
        var angle = (rotationQuarterTurns - 1) * 90d;
        DeviceMapCanvas.LayoutTransform = new RotateTransform(angle);
        DeviceContentRotationAngle = -angle;
    }

    private int LoadDeviceRotation()
    {
        try
        {
            if (!File.Exists(uiStatePath)) return 1;
            var state = JsonSerializer.Deserialize<WindowsUIState>(File.ReadAllText(uiStatePath));
            return state is null ? 1 : ((state.DeviceRotationQuarterTurns % 4) + 4) % 4;
        }
        catch
        {
            return 1;
        }
    }

    private void SaveDeviceRotation()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(uiStatePath) ?? ".");
            var temporary = uiStatePath + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(
                new WindowsUIState(rotationQuarterTurns),
                new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, uiStatePath, true);
        }
        catch (Exception error)
        {
            InputText.Text = $"デバイスの向きを保存できませんでした: {error.Message}";
        }
    }

    private void GroupButtonClick(object sender, RoutedEventArgs e)
    {
        if (sender is RadioButton { Tag: string value } && int.TryParse(value, out var group))
        {
            ShowGroup(group);
            runtime.SetGroup(group);
        }
    }

    private void ShowGroup(int group)
    {
        currentGroup = group;
        if (!configuration.Profiles.TryGetValue(configuration.DefaultProfile, out var profile)) return;
        var mapping = profile.Mapping(group);
        (group switch { 1 => Group1, 2 => Group2, 3 => Group3, _ => Group4 }).IsChecked = true;
        PerformanceMode.IsChecked = mapping.RekordboxMode.Equals("performance", StringComparison.OrdinalIgnoreCase);
        ExportMode.IsChecked = !PerformanceMode.IsChecked;
        RefreshMappings();
    }

    private void ModeButtonClick(object sender, RoutedEventArgs e)
    {
        if (!ready) return;
        if (sender is not RadioButton { Tag: string mode }
            || !configuration.Profiles.TryGetValue(configuration.DefaultProfile, out var profile)) return;
        var mapping = profile.Mapping(currentGroup);
        mapping.RekordboxMode = mode;
        profile.GroupMappings[currentGroup.ToString()] = mapping;
        runtime.SetMode(mode);
        RefreshMappings();
    }

    private void SearchTextChanged(object sender, TextChangedEventArgs e)
    {
        if (SearchPlaceholder is not null)
            SearchPlaceholder.Visibility = string.IsNullOrEmpty(SearchBox.Text) ? Visibility.Visible : Visibility.Collapsed;
        if (ready) RefreshMappings();
    }

    private void ReloadClick(object sender, RoutedEventArgs e)
    {
        try
        {
            var loaded = OverCUEConfiguration.Load(configPath);
            configuration.Version = loaded.Version;
            configuration.DefaultProfile = loaded.DefaultProfile;
            configuration.Profiles = loaded.Profiles;
            configuration.DeviceProfiles = loaded.DeviceProfiles;
            runtime.SetGroup(currentGroup);
            ShowGroup(currentGroup);
            InputText.Text = "設定を再読み込みしました";
        }
        catch (Exception error)
        {
            InputText.Text = $"設定の再読み込みに失敗: {error.Message}";
        }
    }

    private void RefreshMappings()
    {
        if (!configuration.Profiles.TryGetValue(configuration.DefaultProfile, out var profile)) return;
        var query = SearchBox?.Text?.Trim() ?? string.Empty;
        var mapping = profile.Mapping(currentGroup);
        var catalog = RekordboxShortcutCatalog.Load(mapping.RekordboxMode);
        var labelsByTarget = BindingLabels(mapping);

        var internalActions = new (ActionID Action, string Description)[]
        {
            (ActionID.CaptureWaveformPosition, "ポインター位置設定"),
            (ActionID.JogSearchLeft, "Jog Search 左"),
            (ActionID.JogSearchRight, "Jog Search 右"),
            (ActionID.CycleGroup, "グループ切り替え（昇順 1→4）"),
            (ActionID.CycleGroupBackward, "グループ切り替え（降順 4→1）"),
            (ActionID.ToggleRekordboxMode, "EXPORT / PERFORMANCE 切り替え"),
        };
        var overCUERows = internalActions
            .Select(item =>
            {
                var configurationValue = item.Action.ConfigurationValue();
                return new MappingRow(
                    item.Description,
                    $"overcue:{configurationValue}",
                    configurationValue,
                    "OverCUE",
                    labelsByTarget.GetValueOrDefault(configurationValue)?.ToArray() ?? [],
                    IsSelected(configurationValue));
            })
            .Where(row => Matches(row, query))
            .ToArray();
        MappingList.ItemsSource = overCUERows;
        OverCUECountText.Text = query.Length == 0 ? "6" : $"{overCUERows.Length} / 6";

        var allRekordboxRows = catalog.Entries.Select(entry => new MappingRow(
            entry.Description,
            entry.CommandID,
            ConfigurationValue(entry.CommandID),
            entry.Shortcut,
            labelsByTarget.TryGetValue(ConfigurationValue(entry.CommandID), out var labels)
                ? labels.ToArray() : [],
            IsSelected(ConfigurationValue(entry.CommandID))))
            .ToArray();
        var filteredRekordboxRows = allRekordboxRows.Where(row => Matches(row, query)).ToArray();
        RekordboxSections.ItemsSource = Enum.GetValues<RekordboxShortcutCategory>()
            .Select(category => new ShortcutSection(
                CategoryName(category),
                filteredRekordboxRows.Where(row => catalog.Entries.Any(entry =>
                    entry.CommandID.Equals(row.CommandID, StringComparison.OrdinalIgnoreCase)
                    && entry.Category == category)).ToArray(),
                query.Length > 0 || category == RekordboxShortcutCategory.Deck1
                    || filteredRekordboxRows.Any(row => row.IsSelected && catalog.Entries.Any(entry =>
                        entry.CommandID.Equals(row.CommandID, StringComparison.OrdinalIgnoreCase)
                        && entry.Category == category))))
            .Where(section => section.Rows.Count > 0)
            .ToArray();

        if (query.Length > 0) OverCUEExpander.IsExpanded = true;
        PresetText.Text = catalog.MappingName;
        MappingCountText.Text = query.Length == 0
            ? $"{allRekordboxRows.Length}件"
            : $"{filteredRekordboxRows.Length} / {allRekordboxRows.Length}件";
        MappingFileText.Text = string.IsNullOrEmpty(catalog.MappingPath)
            ? "割り当て済みキーマッピングが見つかりません"
            : Path.GetFileName(catalog.MappingPath);
        UpdateDeviceMap(mapping, catalog);
        UpdateSelectedDeviceInputs(mapping);
        ApplyDeviceSelectionStyles();
    }

    private bool IsSelected(string configurationValue) =>
        selectedConfigurationValue?.Equals(configurationValue, StringComparison.OrdinalIgnoreCase) == true;

    private static Dictionary<string, SortedSet<string>> BindingLabels(OverCUEGroupMapping mapping)
    {
        var result = new Dictionary<string, SortedSet<string>>(StringComparer.OrdinalIgnoreCase);
        void Add(string configurationValue, string label)
        {
            if (ActionTarget.Parse(configurationValue) is null) return;
            if (!result.TryGetValue(configurationValue, out var labels))
            {
                labels = new(StringComparer.OrdinalIgnoreCase);
                result[configurationValue] = labels;
            }
            labels.Add(label);
        }

        foreach (var pair in mapping.KeyMap) Add(pair.Value, pair.Key.ToUpperInvariant());
        foreach (var pair in mapping.ChordMap) Add(pair.Value, FormatBinding(pair.Key));
        foreach (var pair in mapping.DialMap)
            Add(pair.Value, pair.Key.Equals("clockwise", StringComparison.OrdinalIgnoreCase) ? "DIAL →" : "DIAL ←");
        foreach (var pair in mapping.DialChordMap) Add(pair.Value, FormatBinding(pair.Key));
        return result;
    }

    private static string ConfigurationValue(string commandID)
    {
        var action = Enum.GetValues<ActionID>().FirstOrDefault(value =>
            RekordboxActionAdapter.CommandID(ActionTarget.ForAction(value))?.Equals(
                commandID, StringComparison.OrdinalIgnoreCase) == true);
        return RekordboxActionAdapter.CommandID(ActionTarget.ForAction(action))?.Equals(
            commandID, StringComparison.OrdinalIgnoreCase) == true
            ? action.ConfigurationValue()
            : $"rekordbox:{commandID}";
    }

    private void UpdateDeviceMap(OverCUEGroupMapping mapping, RekordboxShortcutCatalog catalog)
    {
        foreach (var key in Enum.GetValues<ACK05Key>())
        {
            if (FindName($"Key{key}") is not Button button) continue;
            var keyName = key.ToString().ToUpperInvariant();
            var configurationValue = mapping.KeyMap.GetValueOrDefault(keyName) ?? "unassigned";
            button.Content = new DeviceKeyLabel(
                keyName,
                configurationValue == "unassigned"
                    ? "未割り当て"
                    : ActionName(configurationValue, catalog));
            button.ToolTip = configurationValue == "unassigned"
                ? $"{keyName}: 未割り当て"
                : $"{keyName}: {ActionName(configurationValue, catalog)}";
        }

        DialLeftText.Text = ActionName(
            mapping.DialMap.GetValueOrDefault("counterclockwise") ?? "jog_search_left", catalog);
        DialRightText.Text = ActionName(
            mapping.DialMap.GetValueOrDefault("clockwise") ?? "jog_search_right", catalog);
    }

    private void UpdateSelectedDeviceInputs(OverCUEGroupMapping mapping)
    {
        selectedDeviceKeys.Clear();
        selectedDialDirections.Clear();
        if (selectedConfigurationValue is not { } target) return;

        foreach (var pair in mapping.KeyMap.Where(pair => SameTarget(pair.Value, target)))
            if (Enum.TryParse<ACK05Key>(pair.Key, true, out var key)) selectedDeviceKeys.Add(key);
        foreach (var pair in mapping.ChordMap.Where(pair => SameTarget(pair.Value, target)))
            AddKeys(pair.Key, selectedDeviceKeys);
        foreach (var pair in mapping.DialMap.Where(pair => SameTarget(pair.Value, target)))
            if (Enum.TryParse<DialDirection>(pair.Key, true, out var direction))
                selectedDialDirections.Add(direction);
        foreach (var pair in mapping.DialChordMap.Where(pair => SameTarget(pair.Value, target)))
        {
            AddKeys(pair.Key, selectedDeviceKeys);
            if (pair.Key.Contains("DIAL_RIGHT", StringComparison.OrdinalIgnoreCase))
                selectedDialDirections.Add(DialDirection.Clockwise);
            else if (pair.Key.Contains("DIAL_LEFT", StringComparison.OrdinalIgnoreCase))
                selectedDialDirections.Add(DialDirection.Counterclockwise);
        }
    }

    private static void AddKeys(string input, ISet<ACK05Key> destination)
    {
        foreach (var part in input.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
            if (Enum.TryParse<ACK05Key>(part, true, out var key)) destination.Add(key);
    }

    private static bool SameTarget(string left, string right) =>
        left.Equals(right, StringComparison.OrdinalIgnoreCase);

    private void ApplyDeviceSelectionStyles()
    {
        foreach (var key in Enum.GetValues<ACK05Key>()) ApplyKeyStyle(key);
        ApplyDialStyle(DialDirection.Counterclockwise);
        ApplyDialStyle(DialDirection.Clockwise);
    }

    private void ApplyKeyStyle(ACK05Key key)
    {
        if (FindName($"Key{key}") is not Button button) return;
        var selected = selectedDeviceKeys.Contains(key);
        button.Background = new SolidColorBrush(selected
            ? Color.FromRgb(23, 58, 95)
            : Color.FromRgb(18, 18, 18));
        button.BorderBrush = new SolidColorBrush(selected
            ? Color.FromRgb(10, 132, 255)
            : Color.FromRgb(69, 69, 69));
        button.BorderThickness = new Thickness(selected ? 3 : 1);
        button.Effect = selected ? AccentGlow() : null;
    }

    private void ApplyDialStyle(DialDirection direction)
    {
        var indicator = direction == DialDirection.Clockwise ? DialRightIndicator : DialLeftIndicator;
        var selected = selectedDialDirections.Contains(direction);
        indicator.Background = new SolidColorBrush(selected
            ? Color.FromRgb(23, 58, 95)
            : Colors.Transparent);
        indicator.BorderBrush = new SolidColorBrush(selected
            ? Color.FromRgb(10, 132, 255)
            : Colors.Transparent);
        indicator.BorderThickness = new Thickness(selected ? 3 : 0);
        indicator.Effect = selected ? AccentGlow() : null;
    }

    private static DropShadowEffect AccentGlow() => new()
    {
        Color = Color.FromRgb(10, 132, 255),
        BlurRadius = 14,
        ShadowDepth = 0,
        Opacity = 0.55,
    };

    private static string ActionName(string configurationValue, RekordboxShortcutCatalog catalog)
    {
        if (configurationValue == "unassigned") return "未割り当て";
        var internalName = configurationValue switch
        {
            "hot_cue_1" => "ホットキューAをセット",
            "hot_cue_2" => "ホットキューBをセット",
            "hot_cue_3" => "ホットキューCをセット",
            "delete_hot_cue_1" => "ホットキューAを削除",
            "delete_hot_cue_2" => "ホットキューBを削除",
            "delete_hot_cue_3" => "ホットキューCを削除",
            "set_memory_cue" => "メモリーキュー",
            "delete_memory_cue" => "メモリーキューを削除",
            "call_next_memory_cue" => "次メモリーキュー",
            "call_previous_memory_cue" => "前メモリーキュー",
            "jump_forward" => "前方にジャンプ",
            "jump_backward" => "後方にジャンプ",
            "quantize" => "クオンタイズ",
            "cue" => "キュー",
            "play_pause" => "プレイ/ポーズ",
            "capture_waveform_position" => "ポインター位置設定",
            "jog_search_left" => "Jog Search 左",
            "jog_search_right" => "Jog Search 右",
            "cycle_group" => "グループ切替 +",
            "cycle_group_backward" => "グループ切替 −",
            "toggle_rekordbox_mode" => "モード切替",
            _ => null,
        };
        if (internalName is not null) return internalName;
        var target = ActionTarget.Parse(configurationValue);
        var commandID = target is null ? null : RekordboxActionAdapter.CommandID(target);
        if (commandID is null) return ToTitle(configurationValue);
        var description = catalog.Entries.FirstOrDefault(entry => entry.CommandID.Equals(
            commandID, StringComparison.OrdinalIgnoreCase))?.Description;
        return string.IsNullOrWhiteSpace(description) ? ToTitle(configurationValue) : description.Trim();
    }

    private static string FormatBinding(string value) => value.ToUpperInvariant()
        .Replace("DIAL_LEFT", "DIAL ←", StringComparison.Ordinal)
        .Replace("DIAL_RIGHT", "DIAL →", StringComparison.Ordinal)
        .Replace("+", " + ", StringComparison.Ordinal);

    private static bool Matches(MappingRow row, string query) => query.Length == 0
        || row.Action.Contains(query, StringComparison.OrdinalIgnoreCase)
        || row.CommandID.Contains(query, StringComparison.OrdinalIgnoreCase)
        || row.Shortcut.Contains(query, StringComparison.OrdinalIgnoreCase)
        || row.BindingLabels.Any(label => label.Contains(query, StringComparison.OrdinalIgnoreCase));

    private static string CategoryName(RekordboxShortcutCategory category) => category switch
    {
        RekordboxShortcutCategory.Browse => "ブラウズ",
        RekordboxShortcutCategory.Deck1 => "デッキ1",
        RekordboxShortcutCategory.Deck2 => "デッキ2",
        RekordboxShortcutCategory.AllDecks => "全デッキ",
        RekordboxShortcutCategory.Sampler => "サンプラー",
        RekordboxShortcutCategory.Recordings => "録音",
        RekordboxShortcutCategory.General => "一般",
        RekordboxShortcutCategory.View => "表示",
        RekordboxShortcutCategory.Playlist => "プレイリスト",
        _ => "その他",
    };

    private void DeviceKeyClick(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string rawKey }
            || !Enum.TryParse<ACK05Key>(rawKey, true, out var key)
            || !configuration.Profiles.TryGetValue(configuration.DefaultProfile, out var profile)) return;
        var mapping = profile.Mapping(currentGroup);
        var keyName = KeyLabel(key);
        var direct = mapping.KeyMap.GetValueOrDefault(keyName);
        var target = IsValidTarget(direct) ? direct : PreferredChordTarget(mapping, key);
        if (target is not null) SelectConfigurationAndScroll(target);
        e.Handled = true;
    }

    private void DialIndicatorClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is not Border { Tag: string rawDirection }
            || !configuration.Profiles.TryGetValue(configuration.DefaultProfile, out var profile)) return;
        var mapping = profile.Mapping(currentGroup);
        var direct = mapping.DialMap.GetValueOrDefault(rawDirection);
        string? target = IsValidTarget(direct) ? direct : null;
        if (target is null && selectedConfigurationValue is { } selected)
        {
            var dialToken = rawDirection.Equals("clockwise", StringComparison.OrdinalIgnoreCase)
                ? "DIAL_RIGHT" : "DIAL_LEFT";
            if (mapping.DialChordMap.Any(pair => SameTarget(pair.Value, selected)
                    && pair.Key.Contains(dialToken, StringComparison.OrdinalIgnoreCase)))
                target = selected;
        }
        if (target is not null) SelectConfigurationAndScroll(target);
        e.Handled = true;
    }

    private void ShortcutRowClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is Border { DataContext: MappingRow row })
            SelectConfigurationAndScroll(row.ConfigurationValue);
        e.Handled = true;
    }

    private static bool IsValidTarget(string? target) =>
        !string.IsNullOrWhiteSpace(target) && target != "unassigned" && ActionTarget.Parse(target) is not null;

    private string? PreferredChordTarget(OverCUEGroupMapping mapping, ACK05Key key)
    {
        var keyName = KeyLabel(key);
        var candidates = mapping.ChordMap
            .Concat(mapping.DialChordMap)
            .Where(pair => pair.Key.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
                .Any(part => part.Equals(keyName, StringComparison.OrdinalIgnoreCase)))
            .Where(pair => IsValidTarget(pair.Value))
            .OrderBy(pair => pair.Value, StringComparer.OrdinalIgnoreCase)
            .ToArray();
        if (selectedConfigurationValue is { } selected
            && candidates.Any(pair => SameTarget(pair.Value, selected))) return selected;
        return candidates.FirstOrDefault().Value;
    }

    private void SelectConfigurationAndScroll(string target)
    {
        selectedConfigurationValue = target;
        if (!string.IsNullOrEmpty(SearchBox.Text)) SearchBox.Clear();
        else RefreshMappings();
        Dispatcher.BeginInvoke(ScrollSelectedIntoView, DispatcherPriority.Loaded);
    }

    private void ScrollSelectedIntoView()
    {
        UpdateLayout();
        if (MappingList.Items.Cast<MappingRow>().FirstOrDefault(row => row.IsSelected) is { } internalRow)
        {
            OverCUEExpander.IsExpanded = true;
            MappingList.ScrollIntoView(internalRow);
            UpdateLayout();
        }
        else
        {
            var section = RekordboxSections.Items.Cast<ShortcutSection>()
                .FirstOrDefault(value => value.Rows.Any(row => row.IsSelected));
            if (section is not null
                && RekordboxSections.ItemContainerGenerator.ContainerFromItem(section) is DependencyObject container)
            {
                var expander = FindVisualDescendant<Expander>(container);
                if (expander is not null) expander.IsExpanded = true;
                UpdateLayout();
            }
        }

        var selectedRow = FindVisualDescendant<Border>(ShortcutScrollViewer,
            border => border.DataContext is MappingRow { IsSelected: true });
        if (selectedRow is null) return;
        selectedRow.BringIntoView();
        UpdateLayout();
        try
        {
            var top = selectedRow.TransformToAncestor(ShortcutScrollViewer)
                .Transform(new System.Windows.Point(0, 0)).Y;
            var centeredOffset = ShortcutScrollViewer.VerticalOffset + top
                - (ShortcutScrollViewer.ViewportHeight - selectedRow.ActualHeight) / 2;
            ShortcutScrollViewer.ScrollToVerticalOffset(Math.Max(0, centeredOffset));
        }
        catch (InvalidOperationException)
        {
            selectedRow.BringIntoView();
        }
    }

    private static T? FindVisualDescendant<T>(
        DependencyObject parent,
        Func<T, bool>? predicate = null) where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var child = VisualTreeHelper.GetChild(parent, index);
            if (child is T match && (predicate is null || predicate(match))) return match;
            if (FindVisualDescendant<T>(child, predicate) is { } nested) return nested;
        }
        return null;
    }

    private void MappingDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (MappingList.SelectedItem is MappingRow row) BeginCapture(row);
    }

    private void EditMappingClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: MappingRow row }) BeginCapture(row);
        e.Handled = true;
    }

    private void DeleteMappingClick(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: MappingRow row }
            || !configuration.Profiles.TryGetValue(configuration.DefaultProfile, out var profile)) return;
        var group = IsGlobalAction(row.ConfigurationValue) ? 1 : currentGroup;
        var mapping = profile.GroupMappings.GetValueOrDefault(group.ToString()) ?? new OverCUEGroupMapping();
        RemoveTargetBindings(mapping, row.ConfigurationValue);
        profile.GroupMappings[group.ToString()] = mapping;
        configuration.Save(configPath);
        runtime.SetGroup(currentGroup);
        CancelCapture();
        InputText.Text = $"{row.Action} のACK05割り当てを削除しました";
        RefreshMappings();
        e.Handled = true;
    }

    private void CancelCaptureClick(object sender, RoutedEventArgs e)
    {
        CancelCapture();
        InputText.Text = "キーマップ編集をキャンセルしました";
    }

    private void BeginCapture(MappingRow row)
    {
        editingRow = row;
        previousCaptureKeys.Clear();
        capturedKeyOrder.Clear();
        runtime.ProcessPressedKeys(new HashSet<ACK05Key>());
        CaptureStatusText.Text = $"{row.Action}: ボタン／同時押しを入力するか、ボタンを保持してダイヤルを回してください。";
        CaptureStatusPanel.Visibility = Visibility.Visible;
        InputText.Text = $"編集: {row.Action}";
    }

    private void CancelCapture()
    {
        editingRow = null;
        previousCaptureKeys.Clear();
        capturedKeyOrder.Clear();
        CaptureStatusPanel.Visibility = Visibility.Collapsed;
    }

    private void ProcessDecodedInput(ACK05Event value)
    {
        ShowInput(value);
        if (value is not ACK05Event.Dial dial) return;
        if (editingRow is not null)
            CommitDialCapture(dial.Direction, capturedKeyOrder);
        else
            runtime.ProcessDial(dial.Direction);
    }

    private void ProcessPressedKeys(IReadOnlySet<ACK05Key> keys)
    {
        if (editingRow is null)
        {
            runtime.ProcessPressedKeys(keys);
            return;
        }

        foreach (var key in keys.Except(previousCaptureKeys).OrderBy(value => (int)value))
            if (!capturedKeyOrder.Contains(key)) capturedKeyOrder.Add(key);
        previousCaptureKeys.Clear();
        previousCaptureKeys.UnionWith(keys);
        if (capturedKeyOrder.Count > 0)
            CaptureStatusText.Text = $"入力: {string.Join(" + ", capturedKeyOrder.Select(KeyLabel))} — 離すと保存します";
        if (keys.Count == 0 && capturedKeyOrder.Count > 0) CommitKeyCapture(capturedKeyOrder);
    }

    private void CommitKeyCapture(IEnumerable<ACK05Key> captured)
    {
        if (editingRow is not { } row
            || !configuration.Profiles.TryGetValue(configuration.DefaultProfile, out var profile)) return;
        var keys = captured.ToArray();
        var group = IsGlobalAction(row.ConfigurationValue) ? 1 : currentGroup;
        var mapping = profile.GroupMappings.GetValueOrDefault(group.ToString()) ?? new OverCUEGroupMapping();
        var inputLabel = string.Join("+", keys.Select(KeyLabel));
        var existing = keys.Length == 1
            ? mapping.KeyMap.GetValueOrDefault(inputLabel)
            : mapping.ChordMap.GetValueOrDefault(inputLabel);
        if (!CanOverwrite(inputLabel, existing, row)) return;

        RemoveTargetBindings(mapping, row.ConfigurationValue);
        if (keys.Length == 1) mapping.KeyMap[inputLabel] = row.ConfigurationValue;
        else mapping.ChordMap[inputLabel] = row.ConfigurationValue;
        SaveCapturedMapping(profile, group, mapping, row, FormatBinding(inputLabel));
    }

    private void CommitDialCapture(DialDirection direction, IEnumerable<ACK05Key> held)
    {
        if (editingRow is not { } row
            || !configuration.Profiles.TryGetValue(configuration.DefaultProfile, out var profile)) return;
        var keys = held.ToArray();
        var group = IsGlobalAction(row.ConfigurationValue) ? 1 : currentGroup;
        var mapping = profile.GroupMappings.GetValueOrDefault(group.ToString()) ?? new OverCUEGroupMapping();
        var rawDirection = direction == DialDirection.Clockwise ? "clockwise" : "counterclockwise";
        var rawInput = keys.Length == 0
            ? rawDirection
            : $"{string.Join("+", keys.Select(KeyLabel))}+{(direction == DialDirection.Clockwise ? "DIAL_RIGHT" : "DIAL_LEFT")}";
        var existing = keys.Length == 0
            ? mapping.DialMap.GetValueOrDefault(rawInput)
            : mapping.DialChordMap.GetValueOrDefault(rawInput);
        if (!CanOverwrite(FormatBinding(rawInput), existing, row)) return;

        RemoveTargetBindings(mapping, row.ConfigurationValue);
        if (keys.Length == 0) mapping.DialMap[rawInput] = row.ConfigurationValue;
        else mapping.DialChordMap[rawInput] = row.ConfigurationValue;
        SaveCapturedMapping(profile, group, mapping, row, FormatBinding(rawInput));
    }

    private bool CanOverwrite(string input, string? existing, MappingRow row)
    {
        if (string.IsNullOrEmpty(existing) || existing == "unassigned"
            || existing.Equals(row.ConfigurationValue, StringComparison.OrdinalIgnoreCase)) return true;
        var answer = System.Windows.MessageBox.Show(
            this,
            $"{input} は別の機能に割り当て済みです。\n{row.Action} で上書きしますか？",
            "ACK05キーマップの上書き",
            System.Windows.MessageBoxButton.YesNo,
            System.Windows.MessageBoxImage.Warning);
        if (answer == System.Windows.MessageBoxResult.Yes) return true;
        previousCaptureKeys.Clear();
        capturedKeyOrder.Clear();
        CaptureStatusText.Text = $"{row.Action}: 別の入力を操作してください。";
        return false;
    }

    private void SaveCapturedMapping(
        OverCUEProfile profile,
        int group,
        OverCUEGroupMapping mapping,
        MappingRow row,
        string inputLabel)
    {
        profile.GroupMappings[group.ToString()] = mapping;
        configuration.Save(configPath);
        runtime.SetGroup(currentGroup);
        CancelCapture();
        InputText.Text = $"{row.Action} → {inputLabel}";
        RefreshMappings();
    }

    private static void RemoveTargetBindings(OverCUEGroupMapping mapping, string target)
    {
        foreach (var key in mapping.KeyMap.Where(pair => pair.Value == target).Select(pair => pair.Key).ToArray())
            mapping.KeyMap[key] = "unassigned";
        foreach (var key in mapping.ChordMap.Where(pair => pair.Value == target).Select(pair => pair.Key).ToArray())
            mapping.ChordMap.Remove(key);
        foreach (var key in mapping.DialMap.Where(pair => pair.Value == target).Select(pair => pair.Key).ToArray())
            mapping.DialMap.Remove(key);
        foreach (var key in mapping.DialChordMap.Where(pair => pair.Value == target).Select(pair => pair.Key).ToArray())
            mapping.DialChordMap.Remove(key);
    }

    private static bool IsGlobalAction(string target) =>
        target is "cycle_group" or "cycle_group_backward";

    private static string KeyLabel(ACK05Key key) => key.ToString().ToUpperInvariant();

    private void ShowInput(ACK05Event value)
    {
        switch (value)
        {
            case ACK05Event.KeyDown key:
                InputText.Text = $"入力: {key.Key}";
                _ = HighlightKey(key.Key);
                break;
            case ACK05Event.Dial dial:
                InputText.Text = dial.Direction == DialDirection.Clockwise ? "入力: DIAL →" : "入力: DIAL ←";
                _ = HighlightDial(dial.Direction);
                break;
        }
    }

    private async Task HighlightKey(ACK05Key key)
    {
        var version = highlightVersions.GetValueOrDefault(key) + 1;
        highlightVersions[key] = version;
        if (FindName($"Key{key}") is not Button button) return;
        button.Background = new SolidColorBrush(Color.FromRgb(20, 117, 78));
        button.BorderBrush = new SolidColorBrush(Color.FromRgb(52, 210, 111));
        button.BorderThickness = new Thickness(3);
        button.Effect = new DropShadowEffect
        {
            Color = Color.FromRgb(52, 210, 111),
            BlurRadius = 14,
            ShadowDepth = 0,
            Opacity = 0.6,
        };
        await Task.Delay(220);
        if (highlightVersions.GetValueOrDefault(key) != version) return;
        ApplyKeyStyle(key);
    }

    private async Task HighlightDial(DialDirection direction)
    {
        var version = ++dialHighlightVersion;
        var indicator = direction == DialDirection.Clockwise ? DialRightIndicator : DialLeftIndicator;
        indicator.Background = new SolidColorBrush(Color.FromRgb(20, 117, 78));
        indicator.BorderBrush = new SolidColorBrush(Color.FromRgb(52, 210, 111));
        indicator.BorderThickness = new Thickness(3);
        indicator.Effect = new DropShadowEffect
        {
            Color = Color.FromRgb(52, 210, 111),
            BlurRadius = 14,
            ShadowDepth = 0,
            Opacity = 0.6,
        };
        await Task.Delay(220);
        if (dialHighlightVersion != version) return;
        ApplyDialStyle(direction);
    }

    private static string ToTitle(string value) => string.Join(' ', value.Split('_').Select(part =>
        part.Length == 0 ? part : char.ToUpperInvariant(part[0]) + part[1..]));

    private sealed record MappingRow(
        string Action,
        string CommandID,
        string ConfigurationValue,
        string Shortcut,
        IReadOnlyList<string> BindingLabels,
        bool IsSelected)
    {
        public bool IsConfigured => BindingLabels.Count > 0;
    }

    private sealed record DeviceKeyLabel(string Key, string Action);

    private sealed record WindowsUIState(int DeviceRotationQuarterTurns);

    private sealed record ShortcutSection(string Name, IReadOnlyList<MappingRow> Rows, bool IsExpanded)
    {
        public int Count => Rows.Count;
    }
}
