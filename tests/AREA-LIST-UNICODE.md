# AreaList supplementary Unicode conversion failure

Tested September 24, 2026 with 4D 20.8 on Apple Silicon/macOS 26. This defect prevents complete AreaList text editing support. It does not affect ordinary 4D text editors through the same bridge.

This is an accepted, documented vendor limitation for the release. A vendor fix is not a release prerequisite. The adapter's supplementary-input guard remains required until a corrected vendor version passes the reproduction and full editing matrix below.

A project with one text array and one AreaList Pro 11.4.2 area crashes after pasting long supplementary Unicode text and then reading, copying or committing it. No Accessibility Bridge plugin, component or host methods are installed in that project. Guard Malloc stops inside the vendor's `XF::UString::AssignUTF8` conversion. [Sanitized results and stacks](evidence/arealist-unicode.json) retain the passing controls and failures.

| Operation after Paste | First relevant callers above the conversion |
| --- | --- |
| Read `ALP_Area_EntryText` | `DMEntry::GetEntryValue`, `ALP_GetObjectProperty` |
| Read `ALP_Area_EntryValue` into a text pointer | `DMEntry::GetEntryValue`, `ALP_GetObjectProperty` |
| Standard Select All and Copy | `Scintilla4D::CopyToClipboard`, `Scintilla4D::Copy` |
| Move focus to another control to commit | `DMEntry::GetEntryValue`, `DMArea::WriteEntryData`, `DMArea::EndEntry` |

One thousand repetitions of U+1F3B8 reproduce the getter failure. Long ASCII and basic-multilingual-plane text with accented Latin, CJK and combining accents pass the same getter test. The latter result matches NFC normalization. A single supplementary character also passes this small test; that does not establish safe handling of larger strings. The complete repeated-grid fixture also crashes with the 11.4.3b5 preview at the same conversion. The preview was tested in an isolated copy, without changing an application's vendor dependency.

## Prepare a reproduction

Use a disposable project and an isolated clipboard. The Run reproduction button replaces the clipboard with synthetic text, and the expected failure can terminate 4D. The preparer copies a locally supplied vendor bundle; this repository does not redistribute it or a license.

```sh
python3 prepare_vendor_editor_repro.py \
  --area-list-plugin /path/to/ALP.bundle \
  --operation get --text supplementary
```

An existing license can be supplied with `--license-file /path/to/alp.license`. Its copy stays in the ignored project with mode 0600. Alternatively, use the vendor's demonstration mode. Open the generated `build/vendor-editor-repro/Project/VendorEditorRepro.4DProject`, acknowledge its startup notices and click Run reproduction.

For a deterministic memory diagnostic, launch the 4D executable directly from a shell with `DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib` and `MallocNanoZone=0`, supplying the generated project and `--opening-mode interpreted`. Do not route that launch through `arch`, which strips the injected-library environment on the tested machine. Without Guard Malloc, heap corruption may surface later or an individual run may appear to pass.

`Resources/result.json` marks entry into the selected operation. `Resources/settled.json` appears only after the form survives subsequent timer cycles. For commit, reaching “after operation” alone does not prove completion because native focus transfer settles later. Inspect the crash stack as well as these files.

Repeat with `--operation value`, `copy` or `commit`. Use `--text ascii` and `--text bmp` as controls. Retain the generated evidence before removing the disposable directory and preparing the next case.

## Effect on the adapter

The adapter rejects supplementary input before opening or changing an AreaList editor. Other text continues through the existing vendor keyboard editor, preserving its validation and Undo/Redo behavior. The experimental clipboard path was removed because it did not fix this conversion defect. This rejection applies to bridge requests. It does not repair direct user input or vendor operations outside the bridge.

Replacing the getter with Copy does not avoid the failing conversion. The public AppKit text-input client on the tested editor returns an empty substring and zero selection instead of its contents. Changing the vendor's private implementation or silently bypassing its entry/exit validation is not an equivalent accessibility implementation. A vendor fix must pass these reproductions and the full interpreted/compiled editing matrix before this restriction can be removed.
