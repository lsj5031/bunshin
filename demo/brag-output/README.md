# Bunshin in 25 seconds

An edited product tour made with [Brag](https://github.com/latent-spaces/brag)
and [Hyperframes](https://github.com/heygen-com/hyperframes). It shows actual
Bunshin windows using disposable sample files. It is not a screen recording
or a transfer-speed benchmark. No narration or generated product UI.

- `brag.mp4`: 25-second 1920×1080 H.264 video, 30 fps, with music and soft SFX.
- `brag.jpg`: settled verification-result poster, also baked into frame zero.
- `../../docs/images/bunshin-demo.gif`: full-duration silent README preview.
- `brag-plan.md`, `composition-brief.md`: the Brag story and design contract.
- `composition/`: editable five-scene Hyperframes project, local fonts and media.
- `share-copy.txt`: short caption.

## Reproduce

Requires Node.js 22+ and FFmpeg. From `demo/brag-output/composition`:

```powershell
npm run check
npm run render -- --quality delivery -o ../brag.mp4
```

The package scripts pin Hyperframes 0.9.13. GSAP 3.15.0 and media are local so
the composition needs no runtime network fetches. The CLI itself may download
its rendering browser on first use.

After rendering, extract the settled success frame as a poster, replace frame
zero with that image, and convert the complete movie to the README GIF:

```powershell
ffmpeg -y -ss 22 -i ../brag.mp4 -frames:v 1 -q:v 2 ../brag.jpg
ffmpeg -y -i ../brag.mp4 -i ../brag.jpg -filter_complex "[0:v][1:v]overlay=0:0:enable='eq(n,0)'[v]" -map "[v]" -map "0:a?" -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a copy -movflags +faststart ../brag.poster.mp4
Move-Item ../brag.poster.mp4 ../brag.mp4 -Force
ffmpeg -y -i ../brag.mp4 -filter_complex "fps=10,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" -loop 0 ../../../docs/images/bunshin-demo.gif
```

## Credits

Music: **Sascha Ende, ende.app**, “Happy Beats / Business Moves Vol. 12”,
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), supplied by Brag.
The track is excerpted, reduced in level and faded for the 25-second tour.
Sound: Kenney Interface Sounds `drop_001.ogg`, CC0, supplied by Brag.
Fonts: Bricolage Grotesque, Space Grotesk and IBM Plex Mono, SIL OFL 1.1;
notices accompany their copies in `composition/assets/fonts`.
GSAP is under the [GSAP Standard License](https://gsap.com/standard-license/),
not the application's MIT license. See the root third-party notices.
