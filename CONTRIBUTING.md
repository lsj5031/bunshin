# Contributing to Bunshin

Thanks for helping make copies easier to trust. Bunshin is an early Windows
preview; small, well-explained changes are welcome.

## Report a problem

Open an issue with your Windows version, Bunshin version, selected mode, source
and destination **types** (local disk / removable disk / network share), and
steps to reproduce using disposable files. Include the expected and actual
verdict. Redact private paths from screenshots and logs before uploading.
Do not attach your original personal files or credentials.

For a vulnerability or a reproducible data-loss flaw, follow [SECURITY.md](SECURITY.md).

## Work locally

Clone the repository on Windows. Install the .NET 10 SDK and PowerShell 7;
Windows PowerShell 5.1 is included with Windows. Python 3 is used by the bounded
protocol checker. No Node tooling is needed for the app; it is used only for
the optional demo video.

```powershell
dotnet build gui\Bunshin.Gui.csproj
dotnet run --project gui\Bunshin.Gui.csproj
dotnet run --project engine-tests --configuration Release
pwsh -NoProfile -File test.ps1
powershell.exe -NoProfile -File test.ps1
pwsh -NoProfile -File qa\Run-Stories.ps1
python spec\check_model.py
python spec\check_model.py --mutate
```

Run the PowerShell suites sequentially; they share temporary fixtures. Use only
disposable source/destination trees. The real UI suite needs an unlocked Windows
desktop and drives native pickers; do not use that desktop during the run:

```powershell
powershell.exe -NoProfile -STA -File gui-interaction.tests.ps1
```

## Send a pull request

- Explain the user-visible problem and the resulting behavior.
- Keep changes focused. Follow the existing C#/WPF and PowerShell patterns.
- Preserve mirror confirmation, overlap guards, honest verdicts and cancellation
  cleanup. A copy completing is not the same as verification succeeding.
- Add a regression case for a behavior fix, through a public interface.
- For a visual change, include actual rendered before/after screenshots and
  keyboard/minimum-size checks. Mockups do not substitute for running the app.
- Include the checks you ran and any remaining limitations.

By submitting a contribution, you agree that your original contribution is
licensed under the repository's MIT license. Preserve third-party notices.
