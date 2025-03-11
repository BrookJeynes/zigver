# Zigver

**Zigver** is a small Unix command-line tool to help you easily manage your 
Zig versions.

- [Installation](#installation)
- [Features](#features)
- [Usage](#usage)
- [Contributing](#contributing)

## Installation
To install Zigver, check the "Releases" page or build locally 
via `zig build --release=safe`.

Then add the following line to your `~/.bashrc`, `~/.profile`, or `~/.zshrc` file.

```bash
export PATH="$HOME/.zig/current:$PATH"
```

## Features
- Install specific Zig versions.
- Keep up-to-date with master.
- Switch between installed Zig versions.
- Remove installed Zig versions.
- Install ZLS along with Zig.

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

## Contributing
Contributions, issues, and feature requests are always welcome! This project is
currently using the latest stable release of Zig (0.14.0).
