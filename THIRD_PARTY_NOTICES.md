# Third-party notices

Minidisc is licensed under the Mozilla Public License 2.0 (see `LICENSE`, `NOTICE` and `COPYRIGHT`). This file lists the third-party code and data it uses, and the terms they come under.

## Upstream projects

- **Minidisc** by NO HIT Dev, <https://github.com/Loriage/Minidisc>. MPL-2.0. This repository is a fork of it.
- **Cassette** by Mathieu Dubart, <https://github.com/CassetteLab/cassette>. MPL-2.0. Minidisc is a fork of Cassette; `NOTICE` asks modified versions to acknowledge it, which the README and the in-app Acknowledgements screen do.

## Swift packages

### SwiftSonic

<https://github.com/MathieuDubart/swiftsonic>, resolved by Swift Package Manager and not vendored in this repository. Used for all Subsonic and OpenSubsonic API calls.

```
MIT License

Copyright (c) 2026 Mathieu Dubart

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Data

### AutoEq

<https://github.com/jaakkopasanen/AutoEq>. The equalizer's headphone search reads AutoEq's published results at run time, and `MinidiscTests/Fixtures/AutoEQ/` holds short excerpts of those results (the index and the Sennheiser HD 600 parametric, fixed-band and graphic presets) for the tests.

```
MIT License

Copyright (c) 2018-2022 Jaakko Pasanen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Online services

The app can talk to these services when you turn the matching feature on. None of their code is included, and each has its own terms: LRCLIB (lyrics), MusicBrainz, Wikidata and Wikimedia Commons (artist images), ListenBrainz, Bandcamp, Lidarr, AudioMuse-AI, and the Anthropic and OpenAI APIs (album recommendations, with your own key).

## Audio

### Winamp mode demo clip

`Minidisc/Resources/Winamp/MinidiscDemo.mp3` ("Minidisc. Minidisc. Minidisc. It really whips the llama's ass!") is an original recording made with text-to-speech, as a homage to Winamp's demo.mp3; it contains no audio from Winamp.

Voice: Piper TTS "en_US-libritts-high" (speaker 6505), trained on LibriTTS by Heiga Zen et al. (CC BY 4.0, http://www.openslr.org/60/), from LibriVox public-domain recordings read by "Elena". Model files from https://huggingface.co/rhasspy/piper-voices (MIT).

## Artwork and trademarks

- The app icon, logo and no-artwork placeholder are photographs of a MiniDisc taken by the fork's author.
- "MiniDisc" is a trademark of Sony Group Corporation. Minidisc is not affiliated with or endorsed by Sony; the name and the photographed disc are used descriptively.
- The Minidisc Gold Winamp skin (`Minidisc/Resources/Winamp/MinidiscGold.wsz`) is original artwork made for this fork, under the project's MPL-2.0 licence.
- "Winamp" is a trademark of its owner. Winamp mode is an homage to Winamp 2; Minidisc is not affiliated with or endorsed by Winamp, and it ships no Winamp code, skins or audio.
