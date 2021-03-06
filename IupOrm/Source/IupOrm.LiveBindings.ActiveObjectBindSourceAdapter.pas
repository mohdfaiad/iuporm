unit IupOrm.LiveBindings.ActiveObjectBindSourceAdapter;

interface

uses
  Data.Bind.ObjectScope, IupOrm.CommonTypes, System.Classes, System.Generics.Collections,
  IupOrm.Context.Properties.Interfaces, IupOrm.LiveBindings.Interfaces,
  IupOrm.LiveBindings.Notification;

type

  TioActiveObjectBindSourceAdapter = class(TObjectBindSourceAdapter, IioContainedBindSourceAdapter, IioActiveBindSourceAdapter, IioNaturalBindSourceAdapterSource)
  strict private
    FWhereStr: String;
    FClassRef: TioClassRef;
    FLocalOwnsObject: Boolean;
    FAutoLoadData: Boolean;
    FAutoPersist: Boolean;
    FReloadDataOnRefresh: Boolean;
    FMasterProperty: IioContextProperty;
    FMasterAdaptersContainer: IioDetailBindSourceAdaptersContainer;
    FDetailAdaptersContainer: IioDetailBindSourceAdaptersContainer;
    FBindSource: IioNotifiableBindSource;
    FonNotify: TioBSANotificationEvent;
//    FNaturalBSA_MasterBindSourceAdapter: IioActiveBindSourceAdapter;  *** NB: Code presente (commented) in the unit body ***
    FInsertObj_Enabled: Boolean;
    FInsertObj_NewObj: TObject;
  private
    // =========================================================================
    // Part for the support of the IioNotifiableBindSource interfaces (Added by IupOrm)
    //  because is not implementing IInterface (NB: RefCount DISABLED)
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
    // =========================================================================
    procedure DoBeforeOpen; override;
    procedure DoBeforeRefresh; override;
    procedure DoBeforeDelete; override;
    procedure DoAfterDelete; override;
    procedure DoAfterPost; override;
    procedure DoAfterScroll; override;
    procedure DoAfterInsert; override;
    procedure SetObjStatus(AObjStatus: TIupOrmObjectStatus);
    function UseObjStatus: Boolean;
    procedure DoNotify(ANotification:IioBSANotification);
    function GetioAutoPersist: Boolean;
    procedure SetioAutoPersist(const Value: Boolean); protected
  public
    constructor Create(AClassRef:TioClassRef; AWhereStr:String; AOwner: TComponent; AObject: TObject; AutoLoadData: Boolean; AOwnsObject: Boolean = True); overload;
    destructor Destroy; override;
    procedure SetMasterAdapterContainer(AMasterAdapterContainer:IioDetailBindSourceAdaptersContainer);
    procedure SetMasterProperty(AMasterProperty: IioContextProperty);
    procedure SetBindSource(ANotifiableBindSource:IioNotifiableBindSource);
    procedure ExtractDetailObject(AMasterObj: TObject);
    procedure Persist(ReloadData:Boolean=False);
    function GetDetailBindSourceAdapter(AOwner:TComponent; AMasterPropertyName:String): TBindSourceAdapter;
    function GetNaturalObjectBindSourceAdapter(AOwner:TComponent): TBindSourceAdapter;
    procedure Append(AObject:TObject); overload;
    procedure Insert(AObject:TObject); overload;
    procedure Notify(Sender:TObject; ANotification:IioBSANotification); virtual;
    procedure Refresh(ReloadData:Boolean); overload;
//    procedure NaturalBSA_SetMasterBindSourceAdapter(AActiveBindSourceAdapter:IioActiveBindSourceAdapter);
    function GetDataObject: TObject;
    procedure SetDataObject(const AObj: TObject; const AOwnsObject:Boolean=True);
    procedure ClearDataObject;
    function GetCurrentOID: Integer;
    function IsDetail: Boolean;

    property ioAutoPersist:Boolean read GetioAutoPersist write SetioAutoPersist;
    property ioOnNotify:TioBSANotificationEvent read FonNotify write FonNotify;
  end;

implementation

uses
  IupOrm, System.Rtti, IupOrm.Context.Factory, System.SysUtils,
  IupOrm.LiveBindings.Factory, IupOrm.Context.Map.Interfaces;

{ TioActiveListBindSourceAdapter<T> }

procedure TioActiveObjectBindSourceAdapter.Append(AObject: TObject);
begin
  // Set sone InsertObj subsystem variables
  // Then call the standard code
  FInsertObj_NewObj := AObject;
  FInsertObj_Enabled := True;
  Self.Append;
end;

procedure TioActiveObjectBindSourceAdapter.ClearDataObject;
begin
  Self.SetDataObject(nil, False);
end;

constructor TioActiveObjectBindSourceAdapter.Create(AClassRef:TioClassRef; AWhereStr: String;
  AOwner: TComponent; AObject: TObject; AutoLoadData: Boolean; AOwnsObject: Boolean);
begin
  FAutoPersist := True;
  FAutoLoadData := AutoLoadData;
  FReloadDataOnRefresh := True;
  inherited Create(AOwner, AObject, AClassRef, AOwnsObject);
  FLocalOwnsObject := AOwnsObject;
  FWhereStr := AWhereStr;
  FClassRef := AClassRef;
  // Set Master & Details adapters reference
  FMasterAdaptersContainer := nil;
  FDetailAdaptersContainer := TioLiveBindingsFactory.DetailAdaptersContainer(Self);
  // Init InsertObj subsystem values
  FInsertObj_Enabled := False;
  FInsertObj_NewObj := nil;
end;

destructor TioActiveObjectBindSourceAdapter.Destroy;
begin
  // Detach itself from MasterAdapterContainer (if it's contained)
  if Assigned(FMasterAdaptersContainer) then
    FMasterAdaptersContainer.RemoveBindSourceAdapter(Self);
  // Free the DetailAdaptersContainer
  FDetailAdaptersContainer.Free;
  inherited;
end;

procedure TioActiveObjectBindSourceAdapter.DoAfterDelete;
begin
  inherited;
  // Send a notification to other ActiveBindSourceAdapters & BindSource
  Notify(
         Self,
         TioLiveBindingsFactory.Notification(Self, Self.Current, ntAfterDelete)
        );
end;

procedure TioActiveObjectBindSourceAdapter.DoAfterInsert;
var
  ObjToFree: TObject;
begin
  // If enabled subsitute the new object with the FInsertObj_NewObj (Append(AObject:TObject))
  //  then destroy the "olr" new object
  if FInsertObj_Enabled then
  begin
    try
      ObjToFree := Self.DataObject;
      ObjToFree.Free;
      Self.SetDataObject(FInsertObj_NewObj);
    finally
      // Reset InsertObj subsystem
      FInsertObj_Enabled := False;
      FInsertObj_NewObj := nil;
    end;
  end;
  // Execute AfterInsert event handler
  inherited;
end;

procedure TioActiveObjectBindSourceAdapter.DoAfterPost;
begin
  inherited;
  Self.SetObjStatus(osDirty);
  // If AutoPersist is enabled then persist
  if Self.FAutoPersist then TIupOrm.Persist(Self.Current);
  // Send a notification to other ActiveBindSourceAdapters & BindSource
  Notify(
         Self,
         TioLiveBindingsFactory.Notification(Self, Self.Current, ntAfterPost)
        );
end;

procedure TioActiveObjectBindSourceAdapter.DoAfterScroll;
begin
  inherited;
  Self.FDetailAdaptersContainer.SetMasterObject(Self.Current);
end;

procedure TioActiveObjectBindSourceAdapter.DoBeforeDelete;
begin
  inherited;
  // If ObjectStatus exists in the class then set it as osDirty
  if Self.UseObjStatus then
  begin
    Self.SetObjStatus(osDeleted);
    Abort;
  end;
  // If AutoPersist is enabled then persist
  if Self.FAutoPersist then TIupOrm.Delete(Self.Current);
end;

procedure TioActiveObjectBindSourceAdapter.DoBeforeOpen;
begin
  inherited;
  // Load the object and assign it to the Adapter
  if FAutoLoadData
    then Self.SetDataObject(   TIupOrm.Load(FClassRef)._Where(FWhereStr).ToObject   );
end;

procedure TioActiveObjectBindSourceAdapter.DoBeforeRefresh;
var
  PrevDataObject: TObject;
begin
  inherited;
  if FReloadDataOnRefresh then
  begin
    // Deactivate the adapter
    Self.Active := False;
    // Get actual DataObject
    PrevDataObject := Self.DataObject;
    // If ActualDataObject is assigned and OwnsObject = True then destroy the object
    if Assigned(PrevDataObject) and Self.FLocalOwnsObject then PrevDataObject.Free;
    // Activate the Adapter (after the adapter fire the onBeforeOpen event that Load
    //  the NewObject
    Self.Active := True;
  end;
end;

procedure TioActiveObjectBindSourceAdapter.DoNotify(
  ANotification: IioBSANotification);
begin
  if Assigned(FonNotify)
    then ioOnNotify(Self, ANotification);
end;

procedure TioActiveObjectBindSourceAdapter.ExtractDetailObject(
  AMasterObj: TObject);
var
  ADetailObj: TObject;
  AValue: TValue;
begin
  ADetailObj := nil;
  // Check parameter, if the MasterObject is not assigned
  //  then close the BSA
  if not Assigned(AMasterObj) then
  begin
    Self.SetDataObject(nil, False);  // 2� parameter false ABSOLUTELY!!!!!!!
    Exit;
  end;
  // Extract master property value
  AValue := FMasterProperty.GetValue(AMasterObj);
  // if not empty extract the detail object
  if not AValue.IsEmpty
    then ADetailObj := AValue.AsObject;
  // Set it to the Adapter itself
  Self.SetDataObject(ADetailObj, False);  // 2� parameter false ABSOLUTELY!!!!!!!
end;

function TioActiveObjectBindSourceAdapter.GetCurrentOID: Integer;
var
  AMap: IioMap;
begin
  // Create context for current child object
  AMap := TioContextFactory.Map(Self.Current.ClassType);
  Result := AMap.GetProperties.GetIdProperty.GetValue(Self.Current).AsInteger;
end;

function TioActiveObjectBindSourceAdapter.GetDataObject: TObject;
begin
  Result := Self.DataObject;
end;

function TioActiveObjectBindSourceAdapter.GetDetailBindSourceAdapter(AOwner:TComponent;
  AMasterPropertyName: String): TBindSourceAdapter;
begin
  // Return the requested DetailBindSourceAdapter and set the current master object
  Result := FDetailAdaptersContainer.GetBindSourceAdapter(AOwner, Self.FClassRef.ClassName, AMasterPropertyName);
  FDetailAdaptersContainer.SetMasterObject(Self.Current);
end;

function TioActiveObjectBindSourceAdapter.GetioAutoPersist: Boolean;
begin
  Result := FAutoPersist;
end;

function TioActiveObjectBindSourceAdapter.GetNaturalObjectBindSourceAdapter(
  AOwner: TComponent): TBindSourceAdapter;
begin
  Result := TioLiveBindingsFactory.NaturalObjectBindSourceAdapter(AOwner, Self);
end;

procedure TioActiveObjectBindSourceAdapter.Insert(AObject: TObject);
begin
  // Set sone InsertObj subsystem variables
  // Then call the standard code
  FInsertObj_NewObj := AObject;
  FInsertObj_Enabled := True;
  Self.Insert;
end;

function TioActiveObjectBindSourceAdapter.IsDetail: Boolean;
begin
  Result := Assigned(FMasterProperty);
end;

//procedure TioActiveObjectBindSourceAdapter.NaturalBSA_SetMasterBindSourceAdapter(
//  AActiveBindSourceAdapter: IioActiveBindSourceAdapter);
//begin
//  Self.FNaturalBSA_MasterBindSourceAdapter := AActiveBindSourceAdapter;
//end;

procedure TioActiveObjectBindSourceAdapter.Notify(Sender: TObject;
  ANotification: IioBSANotification);
begin
  // Fire the event handler
  if Sender <> Self
    then Self.DoNotify(ANotification);
  // Replicate notification to the BindSource
  if Assigned(FBindSource) and (Sender <> TObject(FBindSource))
    then FBindSource.Notify(Self, ANotification);
  // Replicate notification to the DetailAdaptersContainer
  if Sender <> TObject(FDetailAdaptersContainer)
    then FDetailAdaptersContainer.Notify(Self, ANotification);
  // Replicate notification to the MasterAdaptersContainer
  if Assigned(FMasterAdaptersContainer) and (Sender <> TObject(FMasterAdaptersContainer))
    then FMasterAdaptersContainer.Notify(Self, ANotification);
end;

procedure TioActiveObjectBindSourceAdapter.Persist(ReloadData:Boolean=False);
begin
  // Persist
  TIupOrm.Persist(Self.DataObject);
  // Reload
  if ReloadData then Self.DoBeforeOpen;
end;

function TioActiveObjectBindSourceAdapter.QueryInterface(const IID: TGUID;
  out Obj): HResult;
begin
  // RefCount disabled
  if GetInterface(IID, Obj) then
    Result := 0
  else
    Result := E_NOINTERFACE;
end;

procedure TioActiveObjectBindSourceAdapter.Refresh(ReloadData: Boolean);
var
  PrecReloadData: Boolean;
begin
  PrecReloadData := FReloadDataOnRefresh;
  Self.FReloadDataOnRefresh := ReloadData;
  inherited Refresh;
  Self.FReloadDataOnRefresh := PrecReloadData;
end;

procedure TioActiveObjectBindSourceAdapter.SetBindSource(ANotifiableBindSource:IioNotifiableBindSource);
begin
  FBindSource := ANotifiableBindSource;
end;

procedure TioActiveObjectBindSourceAdapter.SetDataObject(const AObj: TObject; const AOwnsObject:Boolean);
begin
  // Disable the adapter
  Self.First;  // Bug
  Self.Active := False;
  // AObj is assigned then set it as DataObject
  //  else set DataObject to nil and set MasterObject to nil
  //  to disable all Details adapters also
  if Assigned(AObj) then
  begin
    inherited SetDataObject(AObj, AOwnsObject);
    Self.FAutoLoadData := False;  // If the DataObject is externally provided then Set FAutoLoadData to false to prevent double values
    Self.Active := True;
  end
  else
  begin
    inherited SetDataObject(nil, AOwnsObject);
    Self.FDetailAdaptersContainer.SetMasterObject(nil);
  end;
end;

procedure TioActiveObjectBindSourceAdapter.SetioAutoPersist(const Value: Boolean);
begin
  FAutoPersist := Value;
end;

procedure TioActiveObjectBindSourceAdapter.SetMasterAdapterContainer(
  AMasterAdapterContainer: IioDetailBindSourceAdaptersContainer);
begin
  FMasterAdaptersContainer := AMasterAdapterContainer;
end;

procedure TioActiveObjectBindSourceAdapter.SetMasterProperty(
  AMasterProperty: IioContextProperty);
begin
  FMasterProperty := AMasterProperty;
end;

procedure TioActiveObjectBindSourceAdapter.SetObjStatus(
  AObjStatus: TIupOrmObjectStatus);
begin
  TioContextFactory.Context(Self.Current.ClassName, nil, Self.Current).ObjectStatus := AObjStatus;
end;

function TioActiveObjectBindSourceAdapter.UseObjStatus: Boolean;
begin
  Result := TioContextFactory.Context(Self.Current.ClassName, nil, Self.Current).ObjStatusExist;
end;

function TioActiveObjectBindSourceAdapter._AddRef: Integer;
begin
  // Nothing, the interfaces support is intended only as LazyLoadable support flag
end;

function TioActiveObjectBindSourceAdapter._Release: Integer;
begin
  // Nothing, the interfaces support is intended only as LazyLoadable support flag
end;

end.
