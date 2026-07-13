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
        trayIcon.ContextMenuStrip.Items.Add("OverCUEを開く", null, (_, _) => ShowMainWindow());
        trayIcon.ContextMenuStrip.Items.Add("終了", null, (_, _) => ExitApplication());
        trayIcon.DoubleClick += (_, _) => ShowMainWindow();
        ShowMainWindow();
    }

    private void ShowMainWindow()
    {
        mainWindow?.Show();
        mainWindow?.Activate();
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
        trayIcon?.Dispose();
        trayIcon = null;
        appIcon?.Dispose();
        appIcon = null;
        mainWindow?.Close();
        Shutdown();
    }
}
