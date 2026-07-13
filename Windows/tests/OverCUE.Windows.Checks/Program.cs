using System.Reflection;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using OverCUE.Windows;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        try
        {
            Run(args);
            Environment.Exit(0);
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error);
            Environment.Exit(1);
        }
    }

    private static void Run(string[] args)
    {
        var localizedScreenshotDirectory = OptionValue(args, "--localized-screenshots");
        var languagePath = Path.Combine(Path.GetTempPath(), $"overcue-language-check-{Guid.NewGuid():N}.txt");
        Environment.SetEnvironmentVariable("OVERCUE_LANGUAGE_PATH", languagePath);
        CheckLocalization();
        CheckOriginalRekordboxMappingFallback();

        var uiStatePath = Path.Combine(Path.GetTempPath(), $"overcue-ui-check-{Guid.NewGuid():N}.json");
        Environment.SetEnvironmentVariable("OVERCUE_UI_STATE_PATH", uiStatePath);
        if (localizedScreenshotDirectory is not null)
            RenderOptions.ProcessRenderMode = RenderMode.SoftwareOnly;
        var window = new MainWindow { Width = 1440, Height = 900 };
        var content = (FrameworkElement)window.Content;
        Layout(content);

        var languageBox = Required<ComboBox>(window, "LanguageBox");
        languageBox.SelectedValue = "en";
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        Check(Required<TextBlock>(window, "SearchPlaceholder").Text == "Search functions, keys, or command IDs",
            "Changing the display language did not update the Windows UI.");
        languageBox.SelectedValue = "ja";
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);

        if (localizedScreenshotDirectory is not null)
            RenderLocalizedScreenshots(localizedScreenshotDirectory);

        var physicalButton = Required<Border>(window, "PhysicalTopButton");
        Check(physicalButton.Width == 28 && physicalButton.Height == 5,
            "The physical top button must be horizontal.");
        Check(physicalButton.Margin.Left == 66 && physicalButton.Margin.Top == 73,
            "The physical top button position changed unexpectedly.");

        var deviceCanvas = Required<Grid>(window, "DeviceMapCanvas");
        var rotateButton = Required<Button>(window, "RotateDeviceButton");
        var initialAngle = (deviceCanvas.LayoutTransform as RotateTransform)?.Angle
            ?? throw new InvalidOperationException("Device rotation transform is missing.");
        rotateButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent, rotateButton));
        var rotatedAngle = ((RotateTransform)deviceCanvas.LayoutTransform).Angle;
        Check(NormalizedAngle(rotatedAngle - initialAngle) == 90,
            "Rotate button must turn the device by 90 degrees.");
        Check(window.DeviceContentRotationAngle == -rotatedAngle,
            "Device labels must remain upright after rotation.");
        if (localizedScreenshotDirectory is null
            && args.Skip(1).FirstOrDefault() is { Length: > 0 } rotatedOutput)
        {
            window.Dispatcher.Invoke(() => { }, DispatcherPriority.Render);
            Layout(content);
            Render(content, rotatedOutput);
        }
        for (var index = 0; index < 3; index++)
            rotateButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent, rotateButton));
        Check(((RotateTransform)deviceCanvas.LayoutTransform).Angle == initialAngle,
            "Four rotations must restore the original orientation.");

        var key = Required<Button>(window, "KeyK9");
        key.RaiseEvent(new RoutedEventArgs(Button.ClickEvent, key));
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        Layout(content);

        var selectedTarget = typeof(MainWindow)
            .GetField("selectedConfigurationValue", BindingFlags.Instance | BindingFlags.NonPublic)
            ?.GetValue(window) as string;
        Check(!string.IsNullOrWhiteSpace(selectedTarget), "Device click did not select a shortcut row.");
        Check(key.BorderBrush is SolidColorBrush { Color: var keyBorder }
            && keyBorder == Color.FromRgb(10, 132, 255),
            "Selected device input does not use the macOS accent color.");

        var sections = Required<ItemsControl>(window, "RekordboxSections");
        Check(SelectedRowCount(sections) == 1, "Exactly one shortcut row should be selected.");
        var scrollViewer = Required<ScrollViewer>(window, "ShortcutScrollViewer");
        Check(scrollViewer.VerticalOffset > 0, "Device click did not scroll the shortcut list.");

        var quantizeRow = FindVisualDescendant<Border>(scrollViewer, border =>
            border.DataContext?.GetType().GetProperty("ConfigurationValue")?.GetValue(border.DataContext)
                as string == "quantize")
            ?? throw new InvalidOperationException("Quantize row was not realized.");
        var rowClick = typeof(MainWindow).GetMethod(
            "ShortcutRowClick",
            BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("ShortcutRowClick is missing.");
        var clickArgs = new MouseButtonEventArgs(Mouse.PrimaryDevice, 0, MouseButton.Left)
        {
            RoutedEvent = UIElement.MouseLeftButtonUpEvent,
        };
        rowClick.Invoke(window, [quantizeRow, clickArgs]);
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        Layout(content);

        var keyK7 = Required<Button>(window, "KeyK7");
        Check(keyK7.BorderBrush is SolidColorBrush { Color: var k7Border }
            && k7Border == Color.FromRgb(10, 132, 255),
            "Shortcut row click did not highlight the assigned device button.");
        Check(key.BorderBrush is SolidColorBrush { Color: var k9Border }
            && k9Border == Color.FromRgb(69, 69, 69),
            "The previous device selection remained highlighted.");

        if (localizedScreenshotDirectory is null
            && args.FirstOrDefault() is { Length: > 0 } output)
            Render(content, output);

        window.Close();
        if (File.Exists(uiStatePath)) File.Delete(uiStatePath);
        if (File.Exists(languagePath)) File.Delete(languagePath);
        Console.WriteLine("OverCUE.Windows checks passed: localization, bidirectional selection, and device marker");
    }

    private static void RenderLocalizedScreenshots(string outputDirectory)
    {
        var screenshots = new[]
        {
            (Language: "ja", FileName: "overcue-windows-ja.png"),
            (Language: "en", FileName: "overcue-windows-en.png"),
            (Language: "zh-Hans", FileName: "overcue-windows-zh-Hans.png"),
        };

        foreach (var screenshot in screenshots)
        {
            var output = Path.Combine(outputDirectory, screenshot.FileName);
            RenderValidatedLanguageScreenshot(screenshot.Language, output);
        }

        AppLocalization.Current.SetLanguage("ja");
    }

    private static void RenderValidatedLanguageScreenshot(string language, string output)
    {
        for (var attempt = 1; attempt <= 8; attempt++)
        {
            if (language == "en") RenderSwitchedLanguageScreenshot(language, output);
            else RenderLanguageScreenshot(language, output);
            if (ScreenshotHasHeaderLogo(output)) return;
        }

        throw new InvalidOperationException($"Could not render a complete {language} screenshot.");
    }

    private static bool ScreenshotHasHeaderLogo(string output)
    {
        using var stream = File.OpenRead(output);
        var decoder = new PngBitmapDecoder(
            stream,
            BitmapCreateOptions.PreservePixelFormat,
            BitmapCacheOption.OnLoad);
        var bitmap = new FormatConvertedBitmap(decoder.Frames[0], PixelFormats.Bgra32, null, 0);
        var stride = bitmap.PixelWidth * 4;
        var pixels = new byte[stride * bitmap.PixelHeight];
        bitmap.CopyPixels(pixels, stride, 0);

        var brightPixels = 0;
        for (var y = 10; y < Math.Min(65, bitmap.PixelHeight); y++)
        for (var x = 10; x < Math.Min(220, bitmap.PixelWidth); x++)
        {
            var offset = y * stride + x * 4;
            if (pixels[offset + 3] > 200
                && (pixels[offset] > 150 || pixels[offset + 1] > 150 || pixels[offset + 2] > 150))
                brightPixels++;
        }

        var logoPixel = 20 * stride + 30 * 4;
        var logoIsVisible = pixels[logoPixel + 3] > 200
            && pixels[logoPixel] > 150
            && pixels[logoPixel + 1] > 150
            && pixels[logoPixel + 2] > 150;
        return logoIsVisible && brightPixels > 500;
    }

    private static void RenderSwitchedLanguageScreenshot(string language, string output)
    {
        AppLocalization.Current.SetLanguage("ja");
        var screenshotWindow = new MainWindow { Width = 1440, Height = 900 };
        var content = (FrameworkElement)screenshotWindow.Content;
        Required<TextBlock>(screenshotWindow, "ConfigPathText").Text =
            @"%LocalAppData%\OverCUE\config.json";
        Required<ComboBox>(screenshotWindow, "LanguageBox").SelectedValue = language;
        screenshotWindow.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        Layout(content);
        Render(content, output);
        screenshotWindow.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        Render(content, output);
        screenshotWindow.Close();
    }

    private static void RenderLanguageScreenshot(string language, string output)
    {
        AppLocalization.Current.SetLanguage(language);
        var screenshotWindow = new MainWindow { Width = 1440, Height = 900 };
        var content = (FrameworkElement)screenshotWindow.Content;
        Required<TextBlock>(screenshotWindow, "ConfigPathText").Text =
            @"%LocalAppData%\OverCUE\config.json";
        screenshotWindow.Show();
        screenshotWindow.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        content.InvalidateMeasure();
        content.InvalidateArrange();
        content.InvalidateVisual();
        Layout(content);
        screenshotWindow.Dispatcher.Invoke(() => { }, DispatcherPriority.Render);
        Render(content, output);
        screenshotWindow.Close();
    }

    private static string? OptionValue(string[] args, string option)
    {
        var index = Array.IndexOf(args, option);
        if (index < 0) return null;
        if (index + 1 >= args.Length || string.IsNullOrWhiteSpace(args[index + 1]))
            throw new ArgumentException($"{option} requires an output directory.");
        return args[index + 1];
    }

    private static void CheckLocalization()
    {
        var localization = AppLocalization.Current;
        localization.Initialize();
        localization.SetLanguage("en");
        Check(localization.Text("shortcuts.title") == "Shortcut Settings", "English localization failed.");
        localization.SetLanguage("zh-Hans");
        Check(localization.Text("shortcuts.title") == "快捷键设置", "Simplified Chinese localization failed.");
        localization.SetLanguage("ja");
        Check(localization.Text("shortcuts.title") == "ショートカット設定", "Japanese localization failed.");
    }

    private static void CheckOriginalRekordboxMappingFallback()
    {
        var baseDirectory = Path.Combine(Path.GetTempPath(), $"overcue-mapping-check-{Guid.NewGuid():N}");
        var mappingsDirectory = Path.Combine(baseDirectory, "KeyMappings");
        Directory.CreateDirectory(mappingsDirectory);
        try
        {
            File.WriteAllText(Path.Combine(baseDirectory, "rekordbox3.settings"), """
                <?xml version="1.0" encoding="UTF-8"?>
                <PROPERTIES>
                  <VALUE name="performaceKeyMapping" val="missing-performance"/>
                  <VALUE name="exportKeyMapping" val="missing-export"/>
                </PROPERTIES>
                """);
            File.WriteAllText(Path.Combine(mappingsDirectory, "rekordbox_0000000000000.mappings"), """
                <?xml version="1.0" encoding="UTF-8"?>
                <PROPERTIES>
                  <VALUE name="keyMappingName" val="Performance 1 (Preset)"/>
                  <VALUE name="keyMappingXml"><KEYMAPPINGS>
                    <MAPPING commandId="3006" description="Play/Pause" key="spacebar"/>
                  </KEYMAPPINGS></VALUE>
                </PROPERTIES>
                """);
            File.WriteAllText(Path.Combine(mappingsDirectory, "rekordbox_0000000000030.mappings"), """
                <?xml version="1.0" encoding="UTF-8"?>
                <PROPERTIES>
                  <VALUE name="keyMappingName" val="Export (Preset)"/>
                  <VALUE name="keyMappingXml"><KEYMAPPINGS>
                    <MAPPING commandId="3007" description="Cue" key="C"/>
                  </KEYMAPPINGS></VALUE>
                </PROPERTIES>
                """);

            var performance = RekordboxShortcutCatalog.Load("performance", baseDirectory);
            Check(Path.GetFileName(performance.MappingPath) == "rekordbox_0000000000000.mappings",
                "Missing Performance mapping must fall back to the original preset.");
            Check(performance.Find("3006")?.VirtualKey == 0x20,
                "Original Performance shortcut was not loaded.");
            var export = RekordboxShortcutCatalog.Load("export", baseDirectory);
            Check(Path.GetFileName(export.MappingPath) == "rekordbox_0000000000030.mappings",
                "Missing Export mapping must fall back to the original preset.");
            Check(export.Find("3007")?.VirtualKey == 'C',
                "Original Export shortcut was not loaded.");
        }
        finally
        {
            Directory.Delete(baseDirectory, recursive: true);
        }
    }

    private static int SelectedRowCount(ItemsControl sections)
    {
        var count = 0;
        foreach (var section in sections.Items)
        {
            var rows = section.GetType().GetProperty("Rows")?.GetValue(section) as System.Collections.IEnumerable;
            if (rows is null) continue;
            foreach (var row in rows)
                if (row.GetType().GetProperty("IsSelected")?.GetValue(row) is true) count++;
        }
        return count;
    }

    private static void Layout(FrameworkElement element)
    {
        var size = new Size(1440, 900);
        element.Measure(size);
        element.Arrange(new Rect(size));
        element.UpdateLayout();
    }

    private static T Required<T>(FrameworkElement root, string name) where T : class =>
        root.FindName(name) as T ?? throw new InvalidOperationException($"Missing {name}.");

    private static T? FindVisualDescendant<T>(
        DependencyObject parent,
        Func<T, bool> predicate) where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var child = VisualTreeHelper.GetChild(parent, index);
            if (child is T match && predicate(match)) return match;
            if (FindVisualDescendant<T>(child, predicate) is { } nested) return nested;
        }
        return null;
    }

    private static void Render(FrameworkElement element, string output)
    {
        var bitmap = new RenderTargetBitmap(
            (int)element.ActualWidth,
            (int)element.ActualHeight,
            96,
            96,
            PixelFormats.Pbgra32);
        bitmap.Render(element);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        Directory.CreateDirectory(Path.GetDirectoryName(output) ?? ".");
        using var stream = File.Create(output);
        encoder.Save(stream);
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private static double NormalizedAngle(double angle) => ((angle % 360) + 360) % 360;
}
