# Bunshin bundled fonts

These offline TTF resources use the display, text, and technical font families
identified in the CSS of https://metic.studio/en by the parent task. Caveat is
intentionally omitted. Downloaded on 2026-11-05 (Pacific/Auckland) from the
official Google Fonts repository, pinned to revision
`bbda7253fc363238b05d97515ca71f8ae49c4fa9`.

## Sources and licenses

All three families are licensed under SIL Open Font License 1.1. The original,
unmodified license and copyright notices are included at this directory's root.
Keep these notices with distributed fonts, including portable distributions.

| Family | Google Fonts source at pinned revision | Original project | Included license |
| --- | --- | --- | --- |
| Bricolage Grotesque | [Variable TTF and OFL](https://github.com/google/fonts/tree/bbda7253fc363238b05d97515ca71f8ae49c4fa9/ofl/bricolagegrotesque) | https://github.com/ateliertriay/bricolage | bricolagegrotesque-OFL.txt |
| Space Grotesk | [Variable TTF and OFL](https://github.com/google/fonts/tree/bbda7253fc363238b05d97515ca71f8ae49c4fa9/ofl/spacegrotesk) | https://github.com/floriankarsten/space-grotesk | spacegrotesk-OFL.txt |
| IBM Plex Mono | [Static TTF and OFL](https://github.com/google/fonts/tree/bbda7253fc363238b05d97515ca71f8ae49c4fa9/ofl/ibmplexmono) | https://github.com/IBM/plex | ibmplexmono-OFL.txt |

Bricolage Grotesque and Space Grotesk license notices specify no Reserved Font
Names. IBM's notice reserves "Plex"; its font is redistributed byte-for-byte
without modifications.

## Static instances and WPF names

| File | WPF family | Weight | Source axes |
| --- | --- | --- | --- |
| BricolageGrotesque-Medium.ttf | Bricolage Grotesque | Medium / 500 | wght=500, opsz=96, wdth=100 |
| BricolageGrotesque-SemiBold.ttf | Bricolage Grotesque | SemiBold / 600 | wght=600, opsz=96, wdth=100 |
| SpaceGrotesk-Regular.ttf | Space Grotesk | Regular / 400 | wght=400 |
| SpaceGrotesk-Medium.ttf | Space Grotesk | Medium / 500 | wght=500 |
| SpaceGrotesk-SemiBold.ttf | Space Grotesk | SemiBold / 600 | wght=600 |
| IBMPlexMono-Regular.ttf | IBM Plex Mono | Regular / 400 | Upstream static font |

The five generated instances use fontTools 4.68.0
`fontTools.varLib.instancer.instantiateVariableFont` with every axis pinned.
Bricolage's optical size and width retain upstream defaults; optical sizing
does not change automatically in these static fonts.

After instancing, the residual `STAT` table is removed: retaining its variable
style labels caused incorrect WPF style/weight detection in the local check.
English Windows and Macintosh name records are normalized as follows:

- IDs 1/2: family plus weight suffix (except Regular), and Regular.
- IDs 16/17: shared typographic family and the requested style.
- IDs 4/6: family plus style, and filename stem (PostScript name).
- ID 3: `Bunshin-static-{filename stem};{head.fontRevision}`.
- Variable naming IDs 21, 22, and 25 are removed.
- `OS/2.usWeightClass` is set to the requested weight; italic/bold selection
  bits are cleared, regular selection is set, and `head.macStyle` italic/bold
  bits are cleared. Copyright and licensing name records are preserved.

Use `./Fonts/#Bricolage Grotesque`, `./Fonts/#Space Grotesk`, and
`./Fonts/#IBM Plex Mono` as the WPF resource family references. Declare the
TTFs as WPF Resources in the application project. No system font installation
or network request is required at runtime.

## Validation

All six files were opened with Windows WPF `GlyphTypeface`, and each family
was resolved through WPF `FontFamily` from this local directory. Real selected
font URIs matched the bundled TTFs; families and weights matched the table.
Bricolage has 597 glyphs per face, Space Grotesk 1001, IBM Plex Mono 1033.
FontTools checked that every file has no `fvar` or `gvar`, unrestricted
embedding (`OS/2.fsType=0`), and complete printable ASCII coverage. WPF reports
Installable embedding rights for all six. No fonts were globally installed.
These checks validate font loading and family selection; application resource
packaging and final visual QA belong to the GUI integration task.

## SHA-256

Original variable inputs:

```text
413e7357809ddd12fd80a96a8a396de0e401638d4acd3cb3e37532f0472ac682  BricolageGrotesque[opsz,wdth,wght].ttf
acad6de1fc93436f5c0f1f4137751ef04f1aea3063e7036535970ffcfbd79f72  SpaceGrotesk[wght].ttf
```

Bundled static outputs:

```text
f68be97df7a3fbc09e11ceafb8df54aa185bed7851b0ecc4d432b0106f8334eb  BricolageGrotesque-Medium.ttf
25f5a31f8d35800e40d556291a8d57e4a2f87dd2b32670d256bd3aee6bde941b  BricolageGrotesque-SemiBold.ttf
6a3412f058c7d8dfd9170c41e85ade48e5156ecb89356110ca57a0a27734af46  IBMPlexMono-Regular.ttf
8555d7514171a47d24ecb4433f318eec56da2f4a1ccf4ff2013db2d7cfcaad59  SpaceGrotesk-Medium.ttf
16c7d68c57ad650068de30f4fe20e7baf6a7d128d1a9e45c65ffe645cf2bd7ef  SpaceGrotesk-Regular.ttf
8378e5bcf6499f3fb7a75ddd0d008acc5abc09a930f43c6780966d52e6075014  SpaceGrotesk-SemiBold.ttf
```
