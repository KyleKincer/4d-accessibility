#pragma once
#import "InternalForms.h"

// A list box 4D draws as a whole into one layer, published as a table of its visible rows.
//
// The model is a dictionary:
//   columns   [{header, x, width}]: each column's title and span in the layer's points
//   header    NSValue rect: the band of column titles, in the layer's points from the bottom left
//   rows      [{cells: [text], area: NSValue rect, selected: @YES/@NO or absent if unknown}]:
//             each visible row, top to bottom, its cells' texts and its area in the layer's
//             points from the bottom left
//   cellActions  @YES: pressing a cell clicks the cell itself, and pressing a row its first cell,
//             for a sheet whose cells the mouse selects one by one
//   menus     @YES: each cell and column header has Show Menu, a secondary click on it, for a
//             sheet that opens a context menu there
//   pointer   @YES: the sheet reads where the pointer is, so its cells' and headers' clicks move it
//   editableColumns  NSIndexSet: the columns whose cells' values can be written; a write
//             edits the cell in place, as AXBInternalFormOverlay's editText describes
// Pressing or selecting a row is an ordinary click on it, as the mouse selects it.
@interface AXBInternalTable : AXBInternalFormElement
- (void)updateWithModel:(NSDictionary *)model;
@end
