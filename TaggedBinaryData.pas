unit TaggedBinaryData;

interface

uses
  SysUtils, Classes,
  AuxTypes;

type
  ETBDException = class(Exception);

  ETBDInvalidValue = class(ETBDException);

  ETBDReadError  = class(ETBDException);
  ETBDWriteError = class(ETBDException);

type
  TTBDContextFlags = UInt8;
  TTBDContextID    = UInt16;
  TTBDTag          = UInt8;

const
  TBD_CTXFLAGS_FLAG_TERMINATE = TTBDContextFlags($80);

  TBD_TAG_CLOSE = TTBDTag(-1);

type
  TTBDWriterAction = (waWriteInit,waWriteContext,waWriteTag);

  TTBDWriterActions = set of TTBDWriterAction;

type
  TTaggedBinaryDataWriter = class(TStream)
  private
    fDestination:     TStream;
    fActions:         TTBDWriterActions;
    fCurrentContext:  TTBDContextID;
    fCurrentTag:      TTBDTag;
  protected
    procedure Initialize(Destination: TStream); virtual;
    procedure Finalize; virtual;
    procedure WriteContext; virtual;
    procedure WriteTag; virtual;
    procedure WriteClose; virtual;
  public
    constructor Create(Destination: TStream);
    destructor Destroy; override;
    Function Read(var Buffer; Count: LongInt): LongInt; override;
    Function Write(const Buffer; Count: LongInt): LongInt; override;
    Function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    procedure SetNextContext(Context: TTBDContextID); virtual;
  {
    SetNextTag returns reference to self, so it can be used for inline tag set
    and write, for example:

      Writer.SetNextTag(15).WriteBuffer(Buff,SizeOf(Buff));

    Of course, if you hate such constructs, do not use it ;)
  }
    Function SetNextTag(Tag: TTBDTag): TStream; virtual;
    property Destination: TStream read fDestination;
    property CurrentContext: TTBDContextID read fCurrentContext;
    property CurrentTag: TTBDTag read fCurrentTag;
  end;

  // shorter alias
  TTBDWriter = TTaggedBinaryDataWriter;

implementation

uses
  BinaryStreaming;

procedure TTaggedBinaryDataWriter.Initialize(Destination: TStream);
begin
If Assigned(Destination) then
  fDestination := Destination
else
  raise ETBDInvalidValue.Create('TTaggedBinaryDataWriter.Initialize: Destination stream not assigned.');
fActions := [waWriteInit];
fCurrentContext := 0;
fCurrentTag := 0;
end;

//------------------------------------------------------------------------------

procedure TTaggedBinaryDataWriter.Finalize;
begin
WriteClose;
fActions := [];
fDestination := nil;
end;

//------------------------------------------------------------------------------

procedure TTaggedBinaryDataWriter.WriteContext;

  Function GetContextFlags: TTBDContextFlags;
  begin
    Result := 0;
  end;

begin
Stream_WriteUInt8(fDestination,TBD_TAG_CLOSE);
Stream_WriteUInt8(fDestination,GetContextFlags);
Stream_WriteUInt16(fDestination,fCurrentContext);
Exclude(fActions,waWriteContext);
end;

//------------------------------------------------------------------------------

procedure TTaggedBinaryDataWriter.WriteTag;
begin
Stream_WriteUInt8(fDestination,fCurrentTag);
Exclude(fActions,waWriteTag);
end;

//------------------------------------------------------------------------------

procedure TTaggedBinaryDataWriter.WriteClose;
var
  FlagsTemp:  TTBDContextFlags;
begin
{
  If waWriteInit is still in actions, then absolutely nothing was written
  into destination up to this point, so keep it at that.
}
If not(waWriteInit in fActions) then
  begin
    // write closing tag
    Stream_WriteUInt8(fDestination,TBD_TAG_CLOSE);
    // write terminating context flags without context id
    Stream_WriteUInt8(fDestination,TBD_CTXFLAGS_FLAG_TERMINATE);
  end;
end;

//==============================================================================

constructor TTaggedBinaryDataWriter.Create(Destination: TStream);
begin
inherited Create;
Initialize(Destination);
end;

//------------------------------------------------------------------------------

destructor TTaggedBinaryDataWriter.Destroy;
begin
Finalize;
inherited;
end;

//------------------------------------------------------------------------------

Function TTaggedBinaryDataWriter.Read(var Buffer; Count: LongInt): LongInt;
begin
raise ETBDReadError.Create('TTBDWriter.Read: Reading not allowed.');
end;

//------------------------------------------------------------------------------

Function TTaggedBinaryDataWriter.Write(const Buffer; Count: LongInt): LongInt;
begin
Exclude(fActions,waWriteInit);
If waWriteContext in fActions then
  WriteContext;
If waWriteTag in fActions then
  WriteTag;
Result := fDestination.Write(Buffer,Count);
end;

//------------------------------------------------------------------------------

Function TTaggedBinaryDataWriter.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
Result := fDestination.Seek(Offset,Origin);
end;

//------------------------------------------------------------------------------

procedure TTaggedBinaryDataWriter.SetNextContext(Context: TTBDContextID);
begin
Include(fActions,waWriteContext);
fCurrentContext := Context;
end;

//------------------------------------------------------------------------------

Function TTaggedBinaryDataWriter.SetNextTag(Tag: TTBDTag): TStream;
begin
If Tag <> TBD_TAG_CLOSE then
  begin
    Include(fActions,waWriteTag);
    fCurrentTag := Tag;
    Result := Self;
  end
else raise ETBDInvalidValue.CreateFmt('TTBDWriter.SetNewTag: Invalid tag (0x%.2x).',[Tag]);
end;

end.
