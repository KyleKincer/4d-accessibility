// Called in the root form. Never stop a newer registration on its behalf.
#DECLARE($context : Object; $failure : Object)
var $current; $guard; $record : Object
var $id : Text
var $process : Integer
$current:=AXB_FormContext
If ($current=Null)
 return
End if
If ($current.session#$context.session)
 return
End if
$context.failure:=OB Copy($failure)
If ((New collection(4D.Object).indexOf(OB Class(Form))=0) && Not(OB Is shared(Form)))
 Form.axbError:=$failure.error
 Form.axbFailure:=$failure
End if
AXB_FormStop($context)
// A window its bridge area serves starts again after a pause, so that one failure, such as a
// value the plugin refuses or an error in a callback, does not leave it inaccessible until it is
// reopened. Each failure soon after a start doubles the pause, up to a minute.
If (AXB_Areas#Null)
 For each ($id; AXB_Areas)
  $record:=AXB_Areas[$id]
  If ((New collection($record.context).indexOf($context)=0) && ($record.state="active"))
   If ((Milliseconds-Num($record.startedAt))>300000)
    $record.retries:=0
   End if
   $record.retries:=Num($record.retries)+1
   $record.state:="retrying"
   $process:=New process("AXB_AreaRetry"; 0; "AXB retry"; $id; $record.window; New collection(1; 2; 4; 8; 16; 32; 60)[Choose($record.retries>7; 6; $record.retries-1)])
  End if
 End for each
End if
$guard:=AXB_PollGuard
If (($guard#Null) & (Value type($guard)=Is object))
 If ($guard.context.session=$context.session)
  ON ERR CALL($guard.previousHandler; ek local)
 End if
End if
If ((Value type($context.onError)=Is object) & ($context.onError#Null))
 $context.onError.call(Null; $failure)
End if
