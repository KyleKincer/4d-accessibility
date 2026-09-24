// The form collector uses this for every ancestor clipping rectangle.
#DECLARE($frame : Collection; $clip : Collection) -> $visible : Boolean
$visible:=False
If (($frame=Null) | ($clip=Null))
 return
End if
If (($frame.length#4) | ($clip.length#4))
 return
End if
// 4D evaluates operators left to right. Group arithmetic before comparisons.
$visible:=($frame[0]<($clip[0]+$clip[2])) & (($frame[0]+$frame[2])>$clip[0]) & ($frame[1]<($clip[1]+$clip[3])) & (($frame[1]+$frame[3])>$clip[1]) & ($clip[2]>0) & ($clip[3]>0)
