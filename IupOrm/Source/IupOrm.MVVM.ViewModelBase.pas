unit IupOrm.MVVM.ViewModelBase;

interface

uses
  System.SysUtils, System.Classes,
  IupOrm.LiveBindings.Interfaces, IupOrm.MVVM.Interfaces, System.Rtti,
  IupOrm.Attributes, IupOrm.LiveBindings.PrototypeBindSource,
  IupOrm.CommonTypes;

type
  TioViewModelBase = class(TDataModule, IioViewModel)
  private
    { Private declarations }
    FViewData: IioViewData;
    FioClassName: String;
    FIoMasterBindSource: TioMasterBindSource;
    FIoMasterPropertyName: String;
    FIoWhere: String;
  protected
// ---------------- Start: section added for IInterface support ---------------
{$IFNDEF AUTOREFCOUNT}
    [Volatile] FRefCount: Integer;
{$ENDIF}
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
// ---------------- End: section added for IInterface support ---------------
    procedure ioLoadViewData;
  public
    { Public declarations }
    [ioMarker('CreateByDataObject')]
    constructor Create(ADataObj:TObject); overload;
    [ioMarker('CreateByBindSourceAdapter')]
    constructor Create(ABindSourceAdapter:IioActiveBindSourceAdapter); overload;
    [ioMarker('CreateByClassName')]
    constructor Create(const AClassName:String; const AioWhere:String=''); overload;
    [ioMarker('CreateByClassRef')]
    constructor Create(const AClassRef:TioClassRef; const AioWhere:String=''); overload;
    [ioMarker('CreateByMasterBindSource')]
    constructor Create(const AMasterBindSource:TioMasterBindSource; const AMasterPropertyName:String=''); overload;
    function ViewData: IioViewData;
    function GetActionByName(AActionName: String): TBasicAction;
    procedure BindActions(const AView:IioView);
    procedure BindAction(const AType:TRttiType; const AView:IioView; const AComponentName, AActionName: String);
// ---------------- Start: section added for IInterface support ---------------
{$IFNDEF AUTOREFCOUNT}
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
    class function NewInstance: TObject; override;
    property RefCount: Integer read FRefCount;
{$ENDIF}
// ---------------- End: section added for IInterface support ---------------
  published
    property ioClassName:String read FioClassName write FioClassName;
    property ioWhere:String read FIoWhere write FIoWhere;
    property ioMasterBindSource:TioMasterBindSource read FIoMasterBindSource write FIoMasterBindSource;
    property ioMasterPropertyName:String read FIoMasterPropertyName write FIoMasterPropertyName;
  end;
// ---------------- Start: section added for IInterface support ---------------
  {$IFNDEF SYSTEM_HPP_DEFINES_OBJECTS}
//  {$NODEFINE TInterfacedObject}         { defined in systobj.h }
  {$ENDIF}
// ---------------- End: section added for IInterface support ---------------


implementation

uses IupOrm.MVVM.Factory, IupOrm.Exceptions, IupOrm.RttiContext.Factory,
     IupOrm.LiveBindings.Factory, Data.Bind.ObjectScope;

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

{ TioViewModel }





// ---------------- Start: section added for IInterface support ---------------
{$IFNDEF AUTOREFCOUNT}
procedure TioViewModelBase.AfterConstruction;
begin
// Release the constructor's implicit refcount
  AtomicDecrement(FRefCount);
end;

procedure TioViewModelBase.BeforeDestruction;
begin
  if RefCount <> 0 then
    Error(reInvalidPtr);
end;

class function TioViewModelBase.NewInstance: TObject;
begin
  Result := inherited NewInstance;
  TioViewModelBase(Result).FRefCount := 1;
end;
{$ENDIF}
// ---------------- End: section added for IInterface support ---------------









function TioViewModelBase.GetActionByName(AActionName: String): TBasicAction;
var
  AObj: TObject;
begin
  // Init
  Result := nil;
  if AActionName.Trim = '' then raise EIupOrmException.Create(Self.ClassName + ': invalid action name!');
  // Find the action
  AObj := Self.FindComponent(AActionName);
  // If found then return the action itself
  if Assigned(AObj) and (AObj is TBasicAction) then
    Exit(AObj as TBasicAction);
  // Else raise an exception
  raise EIupOrmException.Create(Self.ClassName + ': action not found!');
end;

procedure TioViewModelBase.BindAction(const AType:TRttiType; const AView:IioView; const AComponentName, AActionName: String);
var
  AObj: TObject;
  AProp: TRttiProperty;
  AAction: TBasicAction;
  AValue: TValue;
begin
  // Get RttiProperty
  AProp := AType.GetProperty('Action');
  if not Assigned(AProp) then EIupOrmException.Create(Self.ClassName + ': RttiProperty not found!');
  // Get the object
  AObj := AView.FindComponent(AComponentName);
  if not Assigned(AObj) then EIupOrmException.Create(Self.ClassName + ': View component not found!');
  // Get action
  AAction := Self.GetActionByName(AActionName);
  if not Assigned(AAction) then EIupOrmException.Create(Self.ClassName + ': Action not found!');
  // Set the action property of the object
  AValue := TValue.From<TBasicAction>(AAction);
  AProp.SetValue(AObj, AValue);
end;

procedure TioViewModelBase.BindActions(const AView: IioView);
var
  Typ: TRttiType;
  Fld: TRttiField;
  Attr: TCustomAttribute;
begin
  // Retrieve the RttiType of the view
  Typ := TioRttiContextFactory.RttiContext.GetType((AView as TObject).ClassType);
  for Fld in Typ.GetFields do
    for Attr in Fld.GetAttributes do
      if Attr is ioAction then
        Self.BindAction(Fld.FieldType, AView, Fld.Name, ioAction(Attr).Value);
end;

constructor TioViewModelBase.Create(ADataObj: TObject);
begin
  inherited Create(nil);
  FViewData := TioMVVMFactory.ViewData(ADataObj);
end;

constructor TioViewModelBase.Create(ABindSourceAdapter: IioActiveBindSourceAdapter);
begin
  inherited Create(nil);
  FViewData := TioMVVMFactory.ViewData(ABindSourceAdapter);
end;









function TioViewModelBase.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := 0
  else
    Result := E_NOINTERFACE;
end;

function TioViewModelBase.ViewData: IioViewData;
begin
  if not Assigned(FViewData) then Self.ioLoadViewData;
  Result := FViewData;
end;

function TioViewModelBase._AddRef: Integer;
begin
{$IFNDEF AUTOREFCOUNT}
  Result := AtomicIncrement(FRefCount);
{$ELSE}
  Result := __ObjAddRef;
{$ENDIF}
end;

function TioViewModelBase._Release: Integer;
begin
{$IFNDEF AUTOREFCOUNT}
  Result := AtomicDecrement(FRefCount);
  if Result = 0 then
    Destroy;
{$ELSE}
  Result := __ObjRelease;
{$ENDIF}
end;

constructor TioViewModelBase.Create(const AClassName, AioWhere: String);
begin
  inherited Create(nil);
  FioClassName := AClassName;
  FIoWhere := FIoWhere;
end;

constructor TioViewModelBase.Create(const AClassRef: TioClassRef; const AioWhere: String);
begin
  inherited Create(nil);
  FioClassName := AClassRef.ClassName;
  FIoWhere := AioWhere;
end;

constructor TioViewModelBase.Create(const AMasterBindSource: TioMasterBindSource; const AMasterPropertyName: String);
begin
  inherited Create(nil);
  FIoMasterBindSource := AMasterBindSource;
  FIoMasterPropertyName := AMasterPropertyName;
end;

procedure TioViewModelBase.ioLoadViewData;
var
  ABindSourceAdapter: TBindSourceAdapter;
  AActiveBindSourceAdapter: IioActiveBindSourceAdapter;
begin
  if Assigned(FViewData)
  then raise EIupOrmException.Create(Self.ClassName + ': "ViewData" is already assigned!')
  else if (Self.FioClassName = '') and (not Assigned(Self.FIoMasterBindSource))
  then raise EIupOrmException.Create(Self.ClassName + ': "ioClassName" or "ioMasterBindSource" property is required!');
  // If a ViewData object is NOT already assigned then retrieve a
  //  BindSourceAdapter by iupORM anche create it
  if  (not Assigned(FViewData)) then
    // If this is a detail BindSource then retrieve the adapter from the master BindSource
    //  else get the adapter directly from IupOrm
    if Assigned(Self.FIoMasterBindSource)
    then ABindSourceAdapter := TioLiveBindingsFactory.GetBSAfromMasterBindSource(Self, Self.FioMasterBindSource, Self.ioMasterPropertyName)
    else ABindSourceAdapter := TioLiveBindingsFactory.GetBSAfromDB(Self, Self.FioClassName, Self.FioWhere);
  // If the BindSourceAdapter is assigned then extract the IioActiveBindSourceAdapter interface
  //  and creat the ViewData Object
  if Assigned(ABindSourceAdapter) then
  begin
    if Supports(ABindSourceAdapter, IioActiveBindSourceAdapter, AActiveBindSourceAdapter)
    then FViewData := TioMVVMFactory.ViewData(AActiveBindSourceAdapter)
    else raise EIupOrmException.Create(Self.ClassName + ': The BindSourceAdapter does not support the "IioActiveBindSourceAdapter" interface!');
  end;
end;



end.