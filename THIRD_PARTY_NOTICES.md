# Third-party notices

Bunshin's original code and documentation use the [MIT license](LICENSE).
The following third-party materials retain their own licenses.

| Material | Location | License / source |
| --- | --- | --- |
| Bricolage Grotesque, Space Grotesk, IBM Plex Mono | `gui/Fonts`; demo font copies | SIL OFL 1.1. Full notices and pinned upstream provenance in `gui/Fonts`. Demo fonts are unmodified copies of those assets. |
| .NET runtime in portable binaries | Generated portable ZIP | Microsoft's .NET runtime notices accompany the SDK's publish output. See [dotnet runtime license](https://github.com/dotnet/runtime/blob/main/LICENSE.TXT) and [third-party notices](https://github.com/dotnet/runtime/blob/main/THIRD-PARTY-NOTICES.TXT). |
| GSAP 3.15.0, used only to render the demo | `demo/brag-output/composition/assets/gsap.min.js` | Copyright 2026 GreenSock. [GSAP Standard License](https://gsap.com/standard-license/); the original copyright and license URL remain in the script header. This dependency is **not MIT** and is not used by the Bunshin application. |
| Happy Beats / Business Moves Vol. 12 | Demo `assets/music/bed.mp3`; rendered demo soundtrack | Music: Sascha Ende, [ende.app](https://ende.app), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Track supplied by [Brag](https://github.com/latent-spaces/brag). Excerpted, mixed quietly and faded for the tour. |
| `drop_001.ogg` | Demo `assets/sfx/drop.ogg`; rendered soundtrack | Kenney Interface Sounds, [CC0](https://creativecommons.org/publicdomain/zero/1.0/), supplied by Brag. Mixed at scene entrances. |

Brag's planning workflow and Hyperframes were used to produce the demo. The
composition, storyboard and build instructions are included. The application
does not contact those services or require their tools at runtime.
