// Report lifecycle failures without depending on a current Form context.
#DECLARE($reply : Object; $options : Object; $phase : Text)
If (($options#Null) & ($reply#Null))
 If ((Value type($options.onError)=Is object) & ($options.onError#Null))
  If (OB Instance of($options.onError; 4D.Function))
   $options.onError.call(Null; New object("error"; $reply.error; "phase"; $phase))
  End if
 End if
End if
