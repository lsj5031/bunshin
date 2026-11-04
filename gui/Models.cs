using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows.Media;

namespace Bunshin.Gui;

public enum JobState { Queued, Copying, Verifying, Verified, Failed, Cancelled }

public sealed class CopyJob : INotifyPropertyChanged
{
    private JobState _state = JobState.Queued;
    private string _detail = "";
    private string _target = "";
    private string _resolvedTarget = "→ Choose a destination";
    private string _elapsed = "";

    public CopyJob(string source) => Source = source;

    public string Source { get; }

    public string Name
    {
        get
        {
            var trimmed = Source.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            var name = Path.GetFileName(trimmed);
            return string.IsNullOrEmpty(name) ? Source : name;
        }
    }

    public string Target { get => _target; set => Set(ref _target, value); }
    public string ResolvedTarget { get => _resolvedTarget; set => Set(ref _resolvedTarget, value); }

    public JobState State
    {
        get => _state;
        set
        {
            if (!Set(ref _state, value)) return;
            Raise(nameof(StateText));
            Raise(nameof(StateBrush));
            Raise(nameof(IsTerminal));
        }
    }

    public string Detail { get => _detail; set => Set(ref _detail, value); }
    public string Elapsed { get => _elapsed; set => Set(ref _elapsed, value); }

    public bool IsTerminal => _state is JobState.Verified or JobState.Failed or JobState.Cancelled;

    public string StateText => _state switch
    {
        JobState.Queued => "Queued",
        JobState.Copying => "Copying",
        JobState.Verifying => "Verifying",
        JobState.Verified => "Verified",
        JobState.Failed => "Failed",
        _ => "Cancelled"
    };

    public Brush StateBrush => _state switch
    {
        JobState.Verified => Palette.Green,
        JobState.Failed => Palette.Red,
        JobState.Copying => Palette.Blue,
        JobState.Verifying => Palette.Violet,
        _ => Palette.Dim
    };

    public event PropertyChangedEventHandler? PropertyChanged;
    internal void RefreshBrush() => Raise(nameof(StateBrush));

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? property = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        Raise(property);
        return true;
    }

    private void Raise(string? property) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
}

public sealed class VerifyRow : INotifyPropertyChanged
{
    public required string Job { get; init; }
    public required string File { get; init; }
    public required string Status { get; init; }
    public required string Source { get; init; }
    public required string Destination { get; init; }
    public string Size { get; init; } = "";

    public Brush Brush => Status == "OK" ? Palette.Green : Palette.Red;
    public event PropertyChangedEventHandler? PropertyChanged;
    internal void RefreshBrush() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Brush)));
}

public static class Palette
{
    public static Brush Green => Accessible(0x247347);
    public static Brush Red => Accessible(0xB33232);
    public static Brush Blue => Accessible(0x315CE1);
    public static Brush Violet => Accessible(0x6550A2);
    public static Brush Dim => Accessible(0x59645E);
    private static Brush Accessible(int rgb) => System.Windows.SystemParameters.HighContrast
        ? System.Windows.SystemColors.WindowTextBrush
        : new SolidColorBrush(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb));
}
