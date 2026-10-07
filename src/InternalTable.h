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
// Pressing or selecting a row is an ordinary click on it, as the mouse selects it.
@interface AXBInternalTable : AXBInternalFormElement
- (void)updateWithModel:(NSDictionary *)model;
@end
