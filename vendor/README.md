# 4D plugin SDK

C API files from https://github.com/4d/4D-Plugin-SDK at
`cd97d1876d4258b56d2516e8ad2816f4ee93e0b5`, downloaded September 22, 2026.
The upstream MIT license is included beside the files.

One compatibility correction changes the integer initializer in
`PA_GetMainWindowHWND` from `NULL` to `0`. Current Clang rejects the C
pointer-to-integer initialization. No ABI or behavior changes are intended.
