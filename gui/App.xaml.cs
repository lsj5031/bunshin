using System.Configuration;
using System.Data;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace Bunshin.Gui;

/// <summary>
/// Interaction logic for App.xaml
/// </summary>
public partial class App : Application
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    internal static void RoundWindow(Window window)
    {
        // Keep compositor shadows and native hit testing. Older Windows versions
        // ignore the Windows 11 corner preference.
        var round = 2; // DWMWCP_ROUND
        DwmSetWindowAttribute(new WindowInteropHelper(window).Handle, 33, ref round, sizeof(int));
    }
}
