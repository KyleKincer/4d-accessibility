#pragma once
#include "4DPluginAPI.h"
void AXBArea(PA_PluginParameters parameters);

void AXBAreaShutdown();
// The bridge itself described a form in this 4D process: the execution cycle that ends next
// is its own and changes nothing the form shows. Thread-safe.
void AXBAreaNoteOwnCycle(PA_long32 process);
