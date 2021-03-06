unit untMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMXTee.Engine,
  FMXTee.Series, FMXTee.Procs, FMXTee.Chart, FMX.Controls.Presentation,
  FMX.StdCtrls, System.Net.URLClient, System.Net.HttpClient,
  System.Net.HttpClientComponent, System.JSON, FMX.Objects,
  System.IOUtils, VerySimple.Lua, VerySimple.Lua.Lib;

type
  TfrmMain = class(TForm)
    Chart1: TChart;
    Series1: TFastLineSeries;
    Series2: TFastLineSeries;
    lbBPM: TLabel;
    lbSPO2: TLabel;
    NetHTTPClient1: TNetHTTPClient;
    pnAlerta: TPanel;
    Rectangle1: TRectangle;
    Label1: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    Lua : TVerySimpleLua;
    m_bApplicationActive : Boolean;
    procedure PrepareReaderThread(sServerAddress: String);
    procedure AddValuesToGraph(iBPM, iSPO2: Integer);
    procedure InitLuaScript;
    procedure OnLuaError(sMsg: String);
    procedure VerifyAltert(iBPM, iSPO2, iTime : Integer);
    function LuaActionInfo(L: lua_State; iBPM, iSPO2, iTime : integer): Boolean;
    function GetApplicationScriptStoragePath: String;
    { Private declarations }
  public
    { Public declarations }
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  m_bApplicationActive:=True;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  m_bApplicationActive:=False;
  if Assigned(Lua) then
    Lua.Free;
end;

procedure TfrmMain.FormShow(Sender: TObject);
begin
  PrepareReaderThread('http://192.168.0.22');
end;


procedure TfrmMain.AddValuesToGraph(iBPM, iSPO2 : Integer);
begin
  Chart1.Series[0].Add(iSPO2);
  Chart1.Series[1].Add(iBPM);
  if Chart1.Series[0].Count>=60 then
  begin
    With Chart1.BottomAxis do
    begin
      Automatic := true;
      AutomaticMinimum := false;
      Minimum := Maximum - 60;
    end;
  end;
end;

procedure TfrmMain.PrepareReaderThread(sServerAddress : String);
var
  oStream : TStringStream;
  sTemp   : String;
  sBPM    : String;
  sSPO2   : String;
  JSONObj : TJSONObject;
  JSONArray : TJSONArray;
  JSONSensor : TJSONObject;
  dLastRead  : Double;
  dCurrentRead : Double;
  sTimeVal : String;
  iTime : Integer;
begin
    TThread.CreateAnonymousThread(
    procedure
    begin
      dLastRead:=0;
      dCurrentRead:=0;
      iTime:=0;
      while (m_bApplicationActive) do
      begin
        try
          oStream := TStringStream.Create;
          NetHTTPClient1.Get(sServerAddress,oStream);
          sTemp:=oStream.DataString.Trim;
          if sTemp<>'' then
          begin
            JSONObj := TJSONObject.ParseJSONValue( TEncoding.ASCII.GetBytes(sTemp), 0) as TJSONObject;
            try
              sTimeVal:=TJSONValue(JSONObj.Get('elapsed_last_read').JsonValue).ToString;
              sTimeVal:=StringReplace(sTimeVal ,'"','', [rfReplaceAll]);
              dCurrentRead:=Now-StrToTime(sTimeVal);
            except
              dCurrentRead:=Now
            end;
            JSONArray := TJSONArray(JSONObj.Get('data').JsonValue);
            JSONSensor:= TJSONObject(JSONArray.Get(0));
            sBPM:=JSONSensor.Pairs[1].JsonValue.ToString;
            JSONSensor:= TJSONObject(JSONArray.Get(1));
            sSPO2:=JSONSensor.Pairs[1].JsonValue.ToString;
            JSONObj.Free;
          end;
          if dLastRead<>dCurrentRead then
          begin
            dLastRead:=dCurrentRead;
            TThread.Synchronize(TThread.CurrentThread,
            procedure
            begin
              lbBPM.Text:='BPM: ' + sBPM;
              lbSPO2.Text:='SPO2: ' + sSPO2 + '%';
              AddValuesToGraph(StrToIntDef(sBPM,0),StrToIntDef(sSPO2,0));
              VerifyAltert(StrToIntDef(sBPM,0),StrToIntDef(sSPO2,0), iTime);
            end);
          end;
        except
        end;
        if oStream<>nil then
          oStream.Free;
        Inc(iTime);
        Sleep(1000);
      end;
    end).Start;
end;

function TfrmMain.GetApplicationScriptStoragePath : String;
begin
  Result:=System.IOUtils.TPath.GetHomePath +
          System.IOUtils.TPath.DirectorySeparatorChar +
         'IOTHelthMonitor' + System.IOUtils.TPath.DirectorySeparatorChar;
end;

procedure TfrmMain.InitLuaScript;
var
  iLine : Integer;
begin
  Lua := TVerySimpleLua.Create;
  Lua.OnError:= OnLuaError;
  Lua.LibraryPath :=  TPath.Combine(GetApplicationScriptStoragePath,LUA_LIBRARY);
  if FileExists(Lua.LibraryPath) then
  begin
    Lua.FilePath := GetApplicationScriptStoragePath;
    ForceDirectories(Lua.FilePath);
    if FileExists(Lua.FilePath + 'IOTHelthMonitor.lua') then
      Lua.DoFile('IOTHelthMonitor.lua');
  end;
end;

procedure TfrmMain.VerifyAltert(iBPM, iSPO2, iTime : Integer);
begin
  if not(Assigned(Lua)) then
    InitLuaScript;
  pnAlerta.Visible:=LuaActionInfo(Lua.LuaState, iBPM, iSPO2, iTime);
end;


function TfrmMain.LuaActionInfo(L: lua_State; iBPM, iSPO2, iTime : integer): Boolean;
var
  iIndex : Integer;
begin
  try
    Result:=False;
    lua_getglobal(L, 'ActionInfo'); // name of the function
    lua_pushinteger(L, iBPM);  // parameter 1
    lua_pushinteger(L, iSPO2);  // parameter 2
    lua_pushinteger(L, iTime);  // parameter 2
    lua_call(L, 3, 1);  // call function with 1 parameters and 1 result
    Result:=lua_toboolean(L,-1)=1;
    lua_pop(L, 1);  // remove result from stack
  except
  end;
end;

procedure TfrmMain.OnLuaError(sMsg: String);
begin
  Showmessage('Lua Script Error: ' + sMsg);
end;


end.
