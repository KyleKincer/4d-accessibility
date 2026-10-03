// Disposable public-AppKit drawing diagnostic, not production support.
@interface AXHPCellPaint : NSObject
@property(nonatomic, weak) NSView *view;
@property(nonatomic) NSRect frame;
@property(nonatomic, copy) NSString *kind;
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSString *phase;
@property(nonatomic, copy) NSArray *transform;
@end
@implementation AXHPCellPaint
@end
static NSObject *cellPaintLock;
static NSMutableArray<AXHPCellPaint *> *cellPaints;
static NSUInteger paintCalls;
static void ProbeCellDraw(NSCell *cell, NSRect frame, NSView *view, NSString *phase) {
    @synchronized(cellPaintLock) { ++paintCalls; }
    if (!view || cell.stringValue.length > 1024) return;
    AXHPCellPaint *paint=[AXHPCellPaint new];
    paint.view=view; paint.frame=frame; paint.text=cell.stringValue ?: @"";
    paint.phase=phase;
    CGContextRef context=NSGraphicsContext.currentContext.CGContext;
    CGAffineTransform transform=context ? CGContextGetCTM(context) : CGAffineTransformIdentity;
    paint.transform=@[@(transform.a),@(transform.b),@(transform.c),@(transform.d),@(transform.tx),@(transform.ty)];
    paint.kind=[cell isKindOfClass:NSBrowserCell.class] ? @"NSBrowserCell" :
        [cell isKindOfClass:NSTextFieldCell.class] ? @"NSTextFieldCell" :
        [cell isKindOfClass:NSButtonCell.class] ? @"NSButtonCell" : @"NSCell";
    @synchronized(cellPaintLock) {
        if(cellPaints.count>=4000) [cellPaints removeObjectAtIndex:0];
        [cellPaints addObject:paint];
    }
}
typedef void (*CellPainter)(id, SEL, NSRect, NSView *);
#define CELL_PROBE(NAME) \
static IMP NAME##Original; \
static void NAME(id cell, SEL selector, NSRect frame, NSView *view) { \
    ProbeCellDraw(cell,frame,view,@#NAME); \
    ((CellPainter)NAME##Original)(cell,selector,frame,view); \
}
CELL_PROBE(BaseDraw)
CELL_PROBE(BaseInterior)
CELL_PROBE(BrowserDraw)
CELL_PROBE(BrowserInterior)
CELL_PROBE(TextDraw)
CELL_PROBE(TextInterior)
static void CellProbeHook(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method method=class_getInstanceMethod(cls,selector);
    if(!method) return;
    *original=method_getImplementation(method);
    if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))
        class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
}
static void InitializeCellProbe(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cellPaintLock=[NSObject new]; cellPaints=[NSMutableArray new];
        CellProbeHook(NSCell.class,@selector(drawWithFrame:inView:),(IMP)BaseDraw,&BaseDrawOriginal);
        CellProbeHook(NSCell.class,@selector(drawInteriorWithFrame:inView:),(IMP)BaseInterior,&BaseInteriorOriginal);
        CellProbeHook(NSBrowserCell.class,@selector(drawWithFrame:inView:),(IMP)BrowserDraw,&BrowserDrawOriginal);
        CellProbeHook(NSBrowserCell.class,@selector(drawInteriorWithFrame:inView:),(IMP)BrowserInterior,&BrowserInteriorOriginal);
        CellProbeHook(NSTextFieldCell.class,@selector(drawWithFrame:inView:),(IMP)TextDraw,&TextDrawOriginal);
        CellProbeHook(NSTextFieldCell.class,@selector(drawInteriorWithFrame:inView:),(IMP)TextInterior,&TextInteriorOriginal);
    });
}
static NSArray *ReadCellProbe(NSWindow *window) {
    NSArray *paints;
    @synchronized(cellPaintLock) { paints=[cellPaints copy]; }
    NSMutableArray *result=[NSMutableArray new];
    for(AXHPCellPaint *paint in paints) {
        NSView *view=paint.view;
        NSRect r=NSZeroRect;
        if(view && view.window==window) r=[view convertRect:paint.frame toView:window.contentView];
        [result addObject:@{@"viewAlive":@(view!=nil),@"hasWindow":@(view.window!=nil),@"windowMatches":@(view.window==window),@"kind":paint.kind,@"text":paint.text,@"phase":paint.phase,@"ctm":paint.transform,@"rawFrame":@[@(paint.frame.origin.x),@(paint.frame.origin.y),@(paint.frame.size.width),@(paint.frame.size.height)],@"frame":@[@(r.origin.x),@(r.origin.y),@(r.size.width),@(r.size.height)]}];
    }
    return result;
}

static NSDictionary *ProbeView(NSView *view, NSView *root, NSUInteger depth) {
    if (depth > 64) return @{ @"error": @"depthLimit" };
    NSRect r = [view convertRect:view.bounds toView:root];
    NSString *kind = [view isKindOfClass:NSOutlineView.class] ? @"NSOutlineView" :
        [view isKindOfClass:NSTableView.class] ? @"NSTableView" :
        [view isKindOfClass:NSScrollView.class] ? @"NSScrollView" :
        [view isKindOfClass:NSControl.class] ? @"NSControl" : @"NSView";
    NSMutableDictionary *result = [@{@"kind":kind, @"frame":@[@(r.origin.x),@(r.origin.y),@(r.size.width),@(r.size.height)],
        @"flipped":@(view.isFlipped), @"hidden":@(view.isHidden), @"axRole":view.accessibilityRole ?: @""} mutableCopy];
    if ([view isKindOfClass:NSOutlineView.class]) {
        NSOutlineView *outline=(NSOutlineView *)view;
        NSMutableArray *rows=[NSMutableArray new];
        for (NSInteger i=0; i<MIN(outline.numberOfRows,1000); ++i) {
            id item=[outline itemAtRow:i]; NSRect rect=[outline rectOfRow:i]; NSRect disclosure=[outline frameOfOutlineCellAtRow:i];
            [rows addObject:@{@"row":@(i),@"level":@([outline levelForRow:i]),@"expanded":@([outline isItemExpanded:item]),
                @"frame":@[@(rect.origin.x),@(rect.origin.y),@(rect.size.width),@(rect.size.height)],
                @"disclosure":@[@(disclosure.origin.x),@(disclosure.origin.y),@(disclosure.size.width),@(disclosure.size.height)]}];
        }
        result[@"rows"]=rows;
    }
    NSMutableArray *children=[NSMutableArray new];
    for(NSView *child in view.subviews) [children addObject:ProbeView(child,root,depth+1)];
    result[@"children"]=children;
    return result;
}
static NSString *ProbeNativeHierarchy(void *nativeWindow) {
    NSWindow *window=nil;
    for(NSWindow *candidate in NSApp.windows) if((__bridge void *)candidate==nativeWindow) {window=candidate;break;}
    if(!window) return @"{}";
    NSView *top=window.contentView;
    while(top.superview && top.superview.window==window) top=top.superview;
    NSMutableDictionary *result=[ProbeView(top,window.contentView,0) mutableCopy];
    result[@"windowFrame"]=@[@(window.frame.origin.x),@(window.frame.origin.y),@(window.frame.size.width),@(window.frame.size.height)];
    result[@"contentFrame"]=@[@(window.contentView.frame.origin.x),@(window.contentView.frame.origin.y),@(window.contentView.frame.size.width),@(window.contentView.frame.size.height)];
    result[@"mainThread"]=@(NSThread.isMainThread);
    result[@"cellPaints"]=ReadCellProbe(window);
    @synchronized(cellPaintLock) { result[@"paintCalls"]=@(paintCalls); result[@"storedPaints"]=@(cellPaints.count); }
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

