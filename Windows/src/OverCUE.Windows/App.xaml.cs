using System.Windows;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace OverCUE.Windows;

public partial class App : System.Windows.Application
{
    private Forms.NotifyIcon? trayIcon;
    private Drawing.Icon? appIcon;
    private MainWindow? mainWindow;
    private bool exiting;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        AppLocalization.Current.Initialize();
        AppLocalization.Current.ApplyResources(Resources);
        AppLocalization.Current.LanguageChanged += LocalizationChanged;
        mainWindow = new MainWindow();
        mainWindow.Closing += (_, args) =>
        {
            if (exiting) return;
            args.Cancel = true;
            mainWindow.Hide();
        };
        appIcon = LoadApplicationIcon();
        trayIcon = new Forms.NotifyIcon
        {
            Icon = appIcon ?? Drawing.SystemIcons.Application,
            Text = "OverCUE",
            Visible = true,
            ContextMenuStrip = new Forms.ContextMenuStrip(),
        };
        BuildTrayMenu();
        trayIcon.DoubleClick += (_, _) => ShowMainWindow();
        ShowMainWindow();
    }

    private void ShowMainWindow()
    {
        mainWindow?.Show();
        mainWindow?.Activate();
    }

    private void LocalizationChanged()
    {
        AppLocalization.Current.ApplyResources(Resources);
        BuildTrayMenu();
    }

    private void BuildTrayMenu()
    {
        if (trayIcon?.ContextMenuStrip is not { } menu) return;
        menu.Items.Clear();
        menu.Items.Add(AppLocalization.Current.Text("app.show"), null, (_, _) => ShowMainWindow());
        menu.Items.Add(AppLocalization.Current.Text("app.quit"), null, (_, _) => ExitApplication());
    }

    private static Drawing.Icon? LoadApplicationIcon()
    {
        var resource = System.Windows.Application.GetResourceStream(
            new Uri("pack://application:,,,/Assets/OverCUEIcon.ico"));
        if (resource?.Stream is null) return null;
        using (resource.Stream) return new Drawing.Icon(resource.Stream);
    }

    private void ExitApplication()
    {
        exiting = true;
        AppLocalization.Current.LanguageChanged -= LocalizationChanged;
        trayIcon?.Dispose();
        trayIcon = null;
        appIcon?.Dispose();
        appIcon = null;
        mainWindow?.Close();
        Shutdown();
    }
}
