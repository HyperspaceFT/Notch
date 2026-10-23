# MediaRemoteAdapter

A prebuilt copy of [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
(framework `CFBundleVersion` 0.1.0), taken unmodified from the boring.notch source tree.
Its signature is the original ad-hoc one; do not re-sign it.

Since macOS 15.4 only Apple-signed processes may read the system's now-playing information.
With **Read Now Playing from Any App** on (Settings → Island; off by default, since this gets
around a macOS restriction), the Now Playing feature runs `/usr/bin/perl mediaremote-adapter.pl <framework> stream`,
which loads the framework into perl and prints what any app (a browser tab, Music, Spotify, ...)
is playing as JSON lines. `scripts/build-app.sh` copies the framework to
`Notch.app/Contents/Frameworks` and the script to `Notch.app/Contents/Resources`.

Only `mediaremote-adapter.pl` and `MediaRemoteAdapter.framework` are needed at run time; the
upstream test client is left out.
