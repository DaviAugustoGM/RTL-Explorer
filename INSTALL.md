# Installing RTL Explorer

## Windows

Users only need to run `RTL-Explorer-Setup.exe`. The installer is offline and includes Tcl/Tk, Python, Yosys, sv2v, Icarus Verilog and the C++ compiler used by CXXRTL.

Keep the default `RTLExplorer` installation directory. Icarus Verilog for Windows cannot invoke its internal helper programs when its own installation path contains spaces.

To build the installer on the development computer:

```powershell
powershell -ExecutionPolicy Bypass -File packaging\windows\build-installer.ps1
```

When the development tool copies already exist in `D:\RTL_EXP_tools`, building is much faster:

```powershell
powershell -ExecutionPolicy Bypass -File packaging\windows\build-installer.ps1 -ReuseLocalTools
```

The staging area is large. It can be moved to a drive with more free space:

```powershell
powershell -ExecutionPolicy Bypass -File packaging\windows\build-installer.ps1 -ReuseLocalTools -WorkDirectory D:\RTL-Explorer-Build
```

The result is written to `dist\windows\RTL-Explorer-Setup.exe`. Inno Setup is downloaded automatically only on the development computer if its compiler is unavailable.

## Linux

From the source directory, run without `sudo`:

```sh
make install
```

This installs everything under `~/.local/share/rtl-explorer`. Tcl/Tk and the C++ compiler are placed in a private runtime using micromamba; OSS CAD Suite provides Python, Yosys and Icarus. No administrator permission or system package manager is used.

Start the program from the application menu or with:

```sh
rtl-explorer
```

Useful maintenance commands:

```sh
make check
make uninstall
```

For a shared installation managed by an administrator, use `sudo make install-system` and `sudo make uninstall-system`.

Linux x86-64 is fully supported. OSS CAD Suite is also fetched on ARM64, but sv2v must already be available because its upstream project does not publish an ARM64 binary.
