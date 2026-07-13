using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Windows;

namespace OverCUE.Windows;

internal sealed record AppLanguage(string Code, string NativeName);

internal sealed class AppLocalization
{
    public static AppLocalization Current { get; } = new();

    public static IReadOnlyList<AppLanguage> Languages { get; } =
    [
        new("ja", "日本語"),
        new("en", "English"),
        new("zh-Hans", "简体中文"),
    ];

    private readonly Dictionary<string, Dictionary<string, string>> tables =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly string statePath = Environment.GetEnvironmentVariable("OVERCUE_LANGUAGE_PATH")
        ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OverCUE",
            "language.txt");
    private bool initialized;

    public string LanguageCode { get; private set; } = "ja";
    public event Action? LanguageChanged;

    public void Initialize()
    {
        if (initialized) return;
        foreach (var language in Languages)
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Localization", $"{language.Code}.json");
            if (!File.Exists(path)) continue;
            var table = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(path));
            if (table is not null) tables[language.Code] = table;
        }

        if (!tables.ContainsKey("en"))
            throw new InvalidOperationException("Missing Localization/en.json.");
        var saved = ReadSavedLanguage();
        LanguageCode = Languages.Any(value => value.Code.Equals(saved, StringComparison.OrdinalIgnoreCase))
            ? Languages.First(value => value.Code.Equals(saved, StringComparison.OrdinalIgnoreCase)).Code
            : "ja";
        initialized = true;
    }

    public void SetLanguage(string code)
    {
        Initialize();
        var language = Languages.FirstOrDefault(value => value.Code.Equals(code, StringComparison.OrdinalIgnoreCase));
        if (language is null || language.Code == LanguageCode) return;
        LanguageCode = language.Code;
        Directory.CreateDirectory(Path.GetDirectoryName(statePath) ?? ".");
        File.WriteAllText(statePath, LanguageCode);
        LanguageChanged?.Invoke();
    }

    public string Text(string key, params object?[] arguments)
    {
        Initialize();
        var value = tables.GetValueOrDefault(LanguageCode)?.GetValueOrDefault(key)
            ?? tables["en"].GetValueOrDefault(key)
            ?? key;
        for (var index = 0; index < arguments.Length; index++)
        {
            var objectToken = value.IndexOf("%@", StringComparison.Ordinal);
            var integerToken = value.IndexOf("%d", StringComparison.Ordinal);
            var token = objectToken < 0 ? integerToken
                : integerToken < 0 ? objectToken
                : Math.Min(objectToken, integerToken);
            if (token < 0) break;
            var formatted = Convert.ToString(arguments[index], CultureInfo.GetCultureInfo(LanguageCode)) ?? string.Empty;
            value = value.Remove(token, 2).Insert(token, formatted);
        }
        return value;
    }

    public void ApplyResources(ResourceDictionary resources)
    {
        Initialize();
        foreach (var key in tables["en"].Keys)
            resources[$"L10n.{key}"] = Text(key);
    }

    private string? ReadSavedLanguage()
    {
        try { return File.Exists(statePath) ? File.ReadAllText(statePath).Trim() : null; }
        catch { return null; }
    }
}
