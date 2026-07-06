#define AppName "RTL Explorer"
#define AppVersion "0.1.0"
#ifndef StageDir
  #define StageDir "..\..\dist\windows\stage"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist\windows"
#endif

[Setup]
AppId={{75F62EB4-CF39-4D53-98A5-D7A5273C8919}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=RTL Explorer
; Icarus Verilog on Windows cannot invoke its helper programs from a path
; containing spaces, so the default installation folder intentionally has none.
DefaultDirName={localappdata}\Programs\RTLExplorer
DefaultGroupName=RTL Explorer
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=RTL-Explorer-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}
VersionInfoVersion={#AppVersion}

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\RTL Explorer"; Filename: "{app}\runtime\tcl\bin\wish86.exe"; Parameters: """{app}\src\main.tcl"""; WorkingDir: "{app}"
Name: "{autodesktop}\RTL Explorer"; Filename: "{app}\runtime\tcl\bin\wish86.exe"; Parameters: """{app}\src\main.tcl"""; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\runtime\tcl\bin\wish86.exe"; Parameters: """{app}\src\main.tcl"""; WorkingDir: "{app}"; Description: "Open RTL Explorer"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Python can create cache files at runtime. They belong to the bundled
; toolchain and are safe to remove with the application.
Type: filesandordirs; Name: "{app}\tools"
