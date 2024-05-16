<h1 align="center">
    Zigver
</h1>

<div align="center">Cross-platform* version manager for Zig, written in Zig</div>

<br>

Zigver is a small cross-platform command-line tool to help you easily manage your 
Zig versions.

## Features
- Install specific Zig versions.
- Keep up-to-date with master.
- Switch between installed Zig versions.
- Remove installed Zig versions.
- Install ZLS along with Zig.
- Cross-platform.

## Usage
```
-h, --help
        Display this help and exit.

-l, --list
        List installed Zig versions.

-v, --version
        Get the version of Zigver.

-i, --install <str>
        Install a version of Zig. Use `latest` or `master` for nightly builds. Use the --with-zls flag to install ZLS alongside the desired Zig version.

-u, --use <str>
        Use an installed version of Zig.

-r, --remove <str>
        Remove a version of Zig.

    --update
        Update Zig version. Only applicable when running latest. Will update ZLS if installed.

-f, --force
        Force an install/uninstall.

    --with-zls
        Install the corresponding ZLS LSP version. Only supports Zig versions 0.11.0 and above.
```

## Install
To install Zigver, check the "Releases" section in Github and download the 
appropriate version.

Then add the following line to your `~/.bashrc`, `~/.profile`, or `~/.zshrc` file.

```bash
export PATH="$HOME/.zig/current:$PATH"
```

### Contributing
Contributions, issues, and feature requests are always welcome!

### Notes
\* Windows support coming soon!
