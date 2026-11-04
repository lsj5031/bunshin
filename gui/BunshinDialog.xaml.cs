using System.Windows;
using System.Windows.Automation;
using System.Windows.Input;
using System.Windows.Threading;

namespace Bunshin.Gui;

public partial class BunshinDialog : Window
{
    private BunshinDialog(Window owner, string message, string title, bool confirm)
    {
        Resources.MergedDictionaries.Add(owner.Resources);
        InitializeComponent();
        Owner = owner;
        Title = title;
        Message.Text = message;
        Heading.Text = confirm
            ? title.Contains("mirror") ? "Mirror and delete extras?" : "Stop this run and close?"
            : message.StartsWith("The queued sources and destinations overlap.")
                ? "Sources and destinations overlap."
                : "This needs your attention.";
        DeclineButton.Visibility = confirm ? Visibility.Visible : Visibility.Collapsed;
        AcceptButton.IsDefault = !confirm;
        AcceptButton.IsCancel = !confirm;
        AcceptButton.Content = confirm
            ? title.Contains("mirror") ? "Mirror and delete extras" : "Stop safely and close"
            : "OK";
        AutomationProperties.SetAutomationId(AcceptButton, confirm ? "6" : "2");
        SourceInitialized += (_, _) => App.RoundWindow(this);
        Loaded += (_, _) => Dispatcher.InvokeAsync(() => Keyboard.Focus(confirm ? DeclineButton : AcceptButton), DispatcherPriority.Input);
    }

    public static MessageBoxResult Show(Window owner, string message, string title, bool confirm = false)
    {
        var accepted = new BunshinDialog(owner, message, title, confirm).ShowDialog() == true;
        return confirm ? accepted ? MessageBoxResult.Yes : MessageBoxResult.No : MessageBoxResult.OK;
    }

    private void Accept_Click(object sender, RoutedEventArgs e) => DialogResult = true;
    private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
