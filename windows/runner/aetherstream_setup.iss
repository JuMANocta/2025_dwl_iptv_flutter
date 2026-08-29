; Script généré par Gemini pour AetherStream

[Setup]
AppId={{com.juman.aetherstream}}
AppName=AetherStream
AppVersion=1.15.9
AppPublisher=JuMAN
DefaultDirName={autopf}\AetherStream
DefaultGroupName=AetherStream
AllowNoIcons=yes
OutputDir=..\..\build\windows\x64\runner\Release\INSTALLER
OutputBaseFilename=AetherStream_Setup
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\AetherStream.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AetherStream"; Filename: "{app}\AetherStream.exe"
Name: "{autodesktop}\AetherStream"; Filename: "{app}\AetherStream.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\AetherStream.exe"; Description: "{cm:LaunchProgram,AetherStream}"; Flags: nowait postinstall skipifsilent
