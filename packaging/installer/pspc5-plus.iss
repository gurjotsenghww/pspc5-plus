#ifndef MyAppVersion
  #define MyAppVersion "0.3.3"
#endif
#ifndef MyNumericVersion
  #define MyNumericVersion "0.3.3.0"
#endif
#ifndef SourceDir
  #define SourceDir "."
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId={{4B03778F-AC48-46BB-88FC-A0C86E65594A}
AppName=PSPC5 Plus
AppVersion={#MyAppVersion}
AppVerName=PSPC5 Plus {#MyAppVersion}
AppPublisher=PSPC5 Plus Project
AppPublisherURL=https://github.com/gurjotsenghww/pspc5-plus
AppSupportURL=https://github.com/gurjotsenghww/pspc5-plus/issues
AppUpdatesURL=https://github.com/gurjotsenghww/pspc5-plus/releases
VersionInfoVersion={#MyNumericVersion}
VersionInfoCompany=PSPC5 Plus Project
VersionInfoDescription=PSPC5 Plus Installer
VersionInfoProductName=PSPC5 Plus
DefaultDirName={localappdata}\Programs\PSPC5 Plus
DefaultGroupName=PSPC5 Plus
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
OutputDir={#OutputDir}
OutputBaseFilename=PSPC5-Plus-{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\..\assets\windows\pspc5-plus.ico
UninstallDisplayIcon={app}\pspc5-plus.exe
LicenseFile={#SourceDir}\LICENSE
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
RestartApplications=no
UsePreviousAppDir=yes
UsePreviousLanguage=yes
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\pspc5-plus.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\game-run.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\pkgextractor.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\README-PORTABLE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\VERSION"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\assets\branding\pspc5-plus-icon-256.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\docs\*"; DestDir: "{app}\docs"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\assets\branding\*"; DestDir: "{app}\assets\branding"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\PSPC5 Plus"; Filename: "{app}\pspc5-plus.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\PSPC5 Plus"; Filename: "{app}\pspc5-plus.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\pspc5-plus.exe"; Description: "{cm:LaunchProgram,PSPC5 Plus}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
