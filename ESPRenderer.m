#import "ESPRenderer.h"
#import <mach-o/dyld.h>
#import <mach/mach.h>

static bool g_espEnabled = true;
static bool g_showBox = true;
static bool g_showHealth = true;
static bool g_showDistance = true;
static bool g_showLevel = true;

@interface PassThroughWindow : UIWindow
@property (nonatomic, weak) UIView *floatButton;
@property (nonatomic, weak) UIView *menuView;
@end

@implementation PassThroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
    
    if (!view) return nil;
    
    if (view == self.floatButton || [view isDescendantOfView:self.floatButton]) return view;
    if (view == self.menuView || [view isDescendantOfView:self.menuView]) return view;
    
    return nil;
}

@end

@interface ESPView : UIView
@property (nonatomic, assign) ESPEntity *entities;
@property (nonatomic, assign) int entityCount;
@end

@implementation ESPView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    return self;
}

- (void)updateEntities:(ESPEntity *)entities count:(int)count {
    _entities = entities;
    _entityCount = count;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (!g_espEnabled) return;
    if (!_entities || _entityCount == 0) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    
    CGContextSetAllowsAntialiasing(ctx, true);
    CGContextSetShouldAntialias(ctx, true);
    
    for (int i = 0; i < _entityCount; i++) {
        ESPEntity *e = &_entities[i];
        
        if (!e->onScreen) continue;
        if (e->isDead) continue;
        if (e->isSelf) continue;
        if (e->hpMax <= 0) continue;
        
        bool isEnemy = (e->camp == 2);
        UIColor *color = isEnemy 
            ? [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.9]
            : [UIColor colorWithRed:0.2 green:1.0 blue:0.2 alpha:0.9];
        
        if (g_showBox) {
            CGRect boxRect = CGRectMake(
                e->sx - e->boxW / 2,
                e->sy - e->boxH / 2,
                e->boxW,
                e->boxH
            );
            
            CGContextSetShadowWithColor(ctx, CGSizeMake(0, 0), 4.0, color.CGColor);
            CGContextSetStrokeColorWithColor(ctx, color.CGColor);
            CGContextSetLineWidth(ctx, 1.5);
            CGContextStrokeRect(ctx, boxRect);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, nil);
            
            CGFloat cl = MIN(8.0, e->boxW / 4);
            CGContextSetLineWidth(ctx, 2.0);
            CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.8].CGColor);
            
            CGContextMoveToPoint(ctx, boxRect.origin.x, boxRect.origin.y + cl);
            CGContextAddLineToPoint(ctx, boxRect.origin.x, boxRect.origin.y);
            CGContextAddLineToPoint(ctx, boxRect.origin.x + cl, boxRect.origin.y);
            CGContextStrokePath(ctx);
            
            CGContextMoveToPoint(ctx, boxRect.origin.x + boxRect.size.width - cl, boxRect.origin.y);
            CGContextAddLineToPoint(ctx, boxRect.origin.x + boxRect.size.width, boxRect.origin.y);
            CGContextAddLineToPoint(ctx, boxRect.origin.x + boxRect.size.width, boxRect.origin.y + cl);
            CGContextStrokePath(ctx);
            
            CGContextMoveToPoint(ctx, boxRect.origin.x, boxRect.origin.y + boxRect.size.height - cl);
            CGContextAddLineToPoint(ctx, boxRect.origin.x, boxRect.origin.y + boxRect.size.height);
            CGContextAddLineToPoint(ctx, boxRect.origin.x + cl, boxRect.origin.y + boxRect.size.height);
            CGContextStrokePath(ctx);
            
            CGContextMoveToPoint(ctx, boxRect.origin.x + boxRect.size.width - cl, boxRect.origin.y + boxRect.size.height);
            CGContextAddLineToPoint(ctx, boxRect.origin.x + boxRect.size.width, boxRect.origin.y + boxRect.size.height);
            CGContextAddLineToPoint(ctx, boxRect.origin.x + boxRect.size.width, boxRect.origin.y + boxRect.size.height - cl);
            CGContextStrokePath(ctx);
        }
        
        if (g_showHealth && e->hpMax > 0) {
            CGFloat barW = e->boxW + 4;
            CGFloat barH = 4;
            CGFloat barX = e->sx - e->boxW / 2 - 2;
            CGFloat barY = e->sy - e->boxH / 2 - barH - 4;
            
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0 alpha:0.7].CGColor);
            CGContextFillRect(ctx, CGRectMake(barX, barY, barW, barH));
            
            float hpRatio = (float)e->hp / (float)e->hpMax;
            if (hpRatio > 1.0f) hpRatio = 1.0f;
            if (hpRatio < 0.0f) hpRatio = 0.0f;
            
            UIColor *hpColor;
            if (hpRatio > 0.6f) {
                hpColor = [UIColor colorWithRed:0.2 green:0.9 blue:0.2 alpha:0.9];
            } else if (hpRatio > 0.3f) {
                hpColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.2 alpha:0.9];
            } else {
                hpColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:0.9];
            }
            
            CGContextSetFillColorWithColor(ctx, hpColor.CGColor);
            CGContextFillRect(ctx, CGRectMake(barX, barY, barW * hpRatio, barH));
        }
        
        if (g_showDistance) {
            NSString *dist = [NSString stringWithFormat:@"%.0fm", e->distance];
            UIFont *font = [UIFont monospacedDigitSystemFontOfSize:9 weight:UIFontWeightMedium];
            NSDictionary *attrs = @{
                NSFontAttributeName: font,
                NSForegroundColorAttributeName: color,
                NSStrokeWidthAttributeName: @(-2.0),
                NSStrokeColorAttributeName: [UIColor blackColor],
            };
            [dist drawAtPoint:CGPointMake(e->sx - e->boxW/2, e->sy + e->boxH/2 + 3) withAttributes:attrs];
        }
        
        if (g_showLevel) {
            NSString *lvl = [NSString stringWithFormat:@"Lv.%d", e->level];
            UIFont *font = [UIFont monospacedDigitSystemFontOfSize:9 weight:UIFontWeightMedium];
            NSDictionary *attrs = @{
                NSFontAttributeName: font,
                NSForegroundColorAttributeName: [UIColor systemYellowColor],
                NSStrokeWidthAttributeName: @(-2.0),
                NSStrokeColorAttributeName: [UIColor blackColor],
            };
            [lvl drawAtPoint:CGPointMake(e->sx + e->boxW/2 + 2, e->sy - e->boxH/2) withAttributes:attrs];
        }
    }
}

@end

@interface ESPMenuView : UIView
- (void)refreshButtons;
@end

@implementation ESPMenuView {
    UIButton *espBtn;
    UIButton *boxBtn;
    UIButton *hpBtn;
    UIButton *distBtn;
    UIButton *lvlBtn;
    CGPoint lastTouch;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.05 green:0.02 blue:0.02 alpha:0.92];
        self.layer.cornerRadius = 12;
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.6].CGColor;
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, 100, 20)];
        title.text = @"ESP-BOX";
        title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBlack];
        title.textColor = [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1];
        [self addSubview:title];
        
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(frame.size.width - 30, 6, 24, 24);
        [close setTitle:@"✕" forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        close.backgroundColor = [UIColor colorWithRed:0.8 green:0.1 blue:0.1 alpha:0.8];
        close.layer.cornerRadius = 12;
        [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:close];
        
        espBtn = [self makeButton:@"ESP: ON" y:34 action:@selector(togESP)];
        boxBtn = [self makeButton:@"Box: ON" y:74 action:@selector(togBox)];
        hpBtn = [self makeButton:@"HP: ON" y:114 action:@selector(togHP)];
        distBtn = [self makeButton:@"Dist: ON" y:154 action:@selector(togDist)];
        lvlBtn = [self makeButton:@"Lv: ON" y:194 action:@selector(togLv)];
        
        [self addSubview:espBtn];
        [self addSubview:boxBtn];
        [self addSubview:hpBtn];
        [self addSubview:distBtn];
        [self addSubview:lvlBtn];
    }
    return self;
}

- (UIButton *)makeButton:(NSString *)title y:(CGFloat)y action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(8, y, 154, 36);
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightBold];
    btn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
    btn.layer.cornerRadius = 6;
    btn.layer.borderWidth = 1;
    btn.layer.borderColor = [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:0.4].CGColor;
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)refreshButtons {
    [espBtn setTitle:g_espEnabled ? @"ESP: ON" : @"ESP: OFF" forState:UIControlStateNormal];
    [boxBtn setTitle:g_showBox ? @"Box: ON" : @"Box: OFF" forState:UIControlStateNormal];
    [hpBtn setTitle:g_showHealth ? @"HP: ON" : @"HP: OFF" forState:UIControlStateNormal];
    [distBtn setTitle:g_showDistance ? @"Dist: ON" : @"Dist: OFF" forState:UIControlStateNormal];
    [lvlBtn setTitle:g_showLevel ? @"Lv: ON" : @"Lv: OFF" forState:UIControlStateNormal];
}

- (void)togESP { g_espEnabled = !g_espEnabled; [self refreshButtons]; }
- (void)togBox { g_showBox = !g_showBox; [self refreshButtons]; }
- (void)togHP { g_showHealth = !g_showHealth; [self refreshButtons]; }
- (void)togDist { g_showDistance = !g_showDistance; [self refreshButtons]; }
- (void)togLv { g_showLevel = !g_showLevel; [self refreshButtons]; }

- (void)closeTapped {
    self.hidden = YES;
    UIButton *fb = nil;
    for (UIView *sub in self.window.subviews) {
        if ([sub isKindOfClass:[UIButton class]]) { fb = (UIButton *)sub; break; }
    }
    fb.hidden = NO;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    lastTouch = [t locationInView:self.superview];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    CGPoint cur = [t locationInView:self.superview];
    self.center = CGPointMake(self.center.x + cur.x - lastTouch.x, self.center.y + cur.y - lastTouch.y);
    lastTouch = cur;
}

@end

@interface ESPFloatButton : UIButton
@end

@implementation ESPFloatButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setTitle:@"E" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBlack];
        self.backgroundColor = [UIColor colorWithRed:0.8 green:0.15 blue:0.15 alpha:0.85];
        self.layer.cornerRadius = frame.size.width / 2;
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:0.6].CGColor;
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.layer.shadowColor = [UIColor redColor].CGColor;
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 6;
        self.layer.shadowOffset = CGSizeZero;
    }
    return self;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    CGPoint loc = [t locationInView:self.superview];
    CGPoint prev = [t previousLocationInView:self.superview];
    self.center = CGPointMake(self.center.x + loc.x - prev.x, self.center.y + loc.y - prev.y);
}

@end

@implementation ESPRenderer {
    PassThroughWindow *window;
    ESPView *espView;
    ESPMenuView *menuView;
    ESPFloatButton *floatButton;
    CADisplayLink *displayLink;
    ESPEntity entities[16];
    Vec3 selfPos;
    bool hasSelf;
    int entityCount;
    int frameTick;
    BOOL running;
}

+ (instancetype)shared {
    static ESPRenderer *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[ESPRenderer alloc] init];
    });
    return shared;
}

- (void)start {
    if (running) return;
    running = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setupWindow];
    });
}

- (void)setupWindow {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)s;
            if (ws.activationState == UISceneActivationStateForegroundActive) {
                scene = ws;
                break;
            }
        }
    }
    
    if (!scene) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (self->running) [self setupWindow];
        });
        return;
    }
    
    window = [[PassThroughWindow alloc] initWithWindowScene:scene];
    window.windowLevel = UIWindowLevelAlert + 100;
    window.backgroundColor = [UIColor clearColor];
    window.opaque = NO;
    window.userInteractionEnabled = YES;
    
    UIView *rootView = [[UIView alloc] initWithFrame:scene.coordinateSpace.bounds];
    rootView.backgroundColor = [UIColor clearColor];
    rootView.userInteractionEnabled = YES;
    
    espView = [[ESPView alloc] initWithFrame:rootView.bounds];
    [rootView addSubview:espView];
    
    floatButton = [[ESPFloatButton alloc] initWithFrame:CGRectMake(16, 250, 44, 44)];
    [floatButton addTarget:self action:@selector(floatTapped) forControlEvents:UIControlEventTouchUpInside];
    [rootView addSubview:floatButton];
    
    menuView = [[ESPMenuView alloc] initWithFrame:CGRectMake(
        UIScreen.mainScreen.bounds.size.width - 190, 120, 170, 260)];
    menuView.hidden = YES;
    [rootView addSubview:menuView];
    
    window.rootViewController = [[UIViewController alloc] init];
    window.rootViewController.view = rootView;
    window.floatButton = floatButton;
    window.menuView = menuView;
    window.hidden = NO;
    
    [self startDisplayLink];
}

- (void)floatTapped {
    menuView.hidden = NO;
    [menuView refreshButtons];
    floatButton.hidden = YES;
}

- (void)startDisplayLink {
    displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderFrame:)];
    displayLink.preferredFramesPerSecond = 30;
    [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)renderFrame:(CADisplayLink *)link {
    if (!running || !espView) return;
    
    frameTick++;
    
    if (frameTick % 3 == 0) {
        entityCount = parseEntities(entities, 16);
        
        hasSelf = NO;
        for (int i = 0; i < entityCount; i++) {
            if (entities[i].isSelf) {
                selfPos = entities[i].pos;
                hasSelf = YES;
                break;
            }
        }
        
        [self projectEntities];
    }
    
    [espView updateEntities:entities count:entityCount];
}

- (void)projectEntities {
    CGRect bounds = [UIScreen mainScreen].bounds;
    float screenW = bounds.size.width;
    float screenH = bounds.size.height;
    
    float camAngle = 0.96;
    float cosA = cosf(camAngle);
    float sinA = sinf(camAngle);
    
    float refX = hasSelf ? selfPos.x : 0;
    float refZ = hasSelf ? selfPos.z : 0;
    
    for (int i = 0; i < entityCount; i++) {
        ESPEntity *e = &entities[i];
        
        float relX = e->pos.x - refX;
        float relZ = e->pos.z - refZ;
        
        float rotX = relX * cosA - relZ * sinA;
        float rotZ = relX * sinA + relZ * cosA;
        
        float scale = screenW / 120.0f;
        
        float sx = screenW / 2 + rotX * scale;
        float sy = screenH / 2 + rotZ * scale * 0.55f - e->pos.y * scale * 0.2f;
        
        if (sx < -100 || sx > screenW + 100 || sy < -100 || sy > screenH + 100) {
            e->onScreen = NO;
            continue;
        }
        
        e->onScreen = YES;
        e->sx = sx;
        e->sy = sy;
        
        float dist = sqrtf(relX * relX + relZ * relZ);
        e->distance = dist;
        
        float boxH = 90.0f - dist * 0.3f;
        if (boxH < 30) boxH = 30;
        if (boxH > 90) boxH = 90;
        
        e->boxH = boxH;
        e->boxW = boxH * 0.55f;
    }
}

- (void)stop {
    running = NO;
    [displayLink invalidate];
    displayLink = nil;
    window.hidden = YES;
    window = nil;
}

@end
