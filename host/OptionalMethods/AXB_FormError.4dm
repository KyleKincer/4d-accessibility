// Called only while AXB_FormPoll owns the local error handler.
var $guard; $failure : Object
$guard:=AXB_PollGuard
$failure:=New object("error"; "callbackError"; "code"; Error; "method"; Error method; "line"; Error line)
// Restore before aborting, so subsequent ordinary UI events keep their handler.
ON ERR CALL($guard.previousHandler; ek local)
AXB_PollGuard:=$guard.previousGuard
$guard.context.active:=False
If ((New collection(4D.Object).indexOf(OB Class($guard.form))=0) && Not(OB Is shared($guard.form)))
 $guard.form.axbError:=$failure.error
 $guard.form.axbFailure:=$failure
End if
// CALL FORM returns to the root even if the failure occurred inside a subform.
// Pass the captured context so delayed cleanup cannot stop a replacement.
CALL FORM($guard.window; Formula(AXB_FormFailed($1; $2)); $guard.context; $failure)
ABORT
