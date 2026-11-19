#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ---------------------------------------------------------------------------
// Pengaturan tampilan (silakan diubah)
// ---------------------------------------------------------------------------
#define kRowH 44.0      // tinggi pill dan diameter lingkaran
#define kSide 14.0      // jarak lingkaran dari tepi layar
#define kGap 8.0        // jarak lingkaran ke pill
#define kLift 6.0       // seberapa tinggi baris diangkat dari posisi toolbar lama
#define kUseScrim 1     // 1 = blur lembut di tepi bawah halaman, 0 = mati
#define kScrimH 110.0   // tinggi area blur tepi bawah

#define kBack 0x5A27
#define kMore 0x5A28
#define kScrim 0x5A29
#define kIcon 0x5A2B

static __weak UIView *gToolbar;
static __weak UIView *gColl;
static char kAlphaKey;
static BOOL gKicked = NO;
static BOOL gInTap = NO;
static CGRect gOldCap, gNewCap;

static NSString *S26Name(UIView *v) { return NSStringFromClass([v class]); }

static CGFloat S26RealAlpha(UIView *t) {
    NSNumber *n = objc_getAssociatedObject(t, &kAlphaKey);
    return n ? n.doubleValue : 1.0;
}

static UIView *S26Find(UIView *v, NSString *cls) {
    if ([S26Name(v) isEqualToString:cls]) return v;
    for (UIView *s in v.subviews) {
        UIView *r = S26Find(s, cls);
        if (r) return r;
    }
    return nil;
}

// ---------------------------------------------------------------------------
// Efek glass
// ---------------------------------------------------------------------------
static UIColor *S26GlassTint(void) {
    static UIColor *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            return tc.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0.10 alpha:0.50]
                : [UIColor colorWithWhite:0.97 alpha:0.56];
        }];
    });
    return c;
}

static char kRadiusKey;

static CALayer *S26NamedLayer(CALayer *parent, NSString *name) {
    for (CALayer *l in parent.sublayers) {
        if ([l.name isEqualToString:name]) return l;
    }
    return nil;
}

// host = view yang membawa bayangan (tombol atau SFCapsuleView)
// fx   = UIVisualEffectView di dalam host yang diberi lapisan glass.
// Lapisan kilau dan cincin ditaruh di contentView (bukan di layer fx), karena
// UIKit membangun ulang isi dalam fx saat tema berubah dan lapisan baru bisa
// menutupi lapisan yang kita tambahkan langsung ke fx.
static void S26ApplyGlass(UIView *host, UIVisualEffectView *fx, CGFloat radius) {
    CGRect b = fx.bounds;
    if (b.size.width < 2.0 || b.size.height < 2.0) return;

    if (!fx.effect) {
        fx.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    }
    UIView *cv = fx.contentView;
    cv.backgroundColor = S26GlassTint();
    fx.clipsToBounds = YES;
    fx.layer.cornerRadius = radius;
    fx.layer.cornerCurve = kCACornerCurveContinuous;
    fx.layer.borderWidth = 0.5;
    fx.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.28].CGColor;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // kilau lembut di bagian atas
    CAGradientLayer *sheen = (CAGradientLayer *)S26NamedLayer(cv.layer, @"s26sheen");
    if (!sheen) {
        sheen = [CAGradientLayer layer];
        sheen.name = @"s26sheen";
        sheen.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.26].CGColor,
                         (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
        sheen.startPoint = CGPointMake(0.5, 0.0);
        sheen.endPoint = CGPointMake(0.5, 1.0);
        [cv.layer addSublayer:sheen];
    }
    CGRect sf = CGRectMake(0, 0, b.size.width, b.size.height * 0.5);
    if (!CGRectEqualToRect(sheen.frame, sf)) sheen.frame = sf;

    // cincin cahaya tipis di tepi: terang di kiri atas, redup di tengah,
    // terang lagi sedikit di kanan bawah
    CAGradientLayer *rim = (CAGradientLayer *)S26NamedLayer(cv.layer, @"s26rim");
    if (!rim) {
        rim = [CAGradientLayer layer];
        rim.name = @"s26rim";
        rim.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.90].CGColor,
                       (id)[UIColor colorWithWhite:1.0 alpha:0.14].CGColor,
                       (id)[UIColor colorWithWhite:1.0 alpha:0.03].CGColor,
                       (id)[UIColor colorWithWhite:1.0 alpha:0.50].CGColor];
        rim.locations = @[@0.0, @0.32, @0.68, @1.0];
        rim.startPoint = CGPointMake(0.0, 0.0);
        rim.endPoint = CGPointMake(1.0, 1.0);
        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.fillRule = kCAFillRuleEvenOdd;
        rim.mask = mask;
        [cv.layer addSublayer:rim];
    }
    CAShapeLayer *rm = (CAShapeLayer *)rim.mask;
    NSNumber *lastR = objc_getAssociatedObject(rim, &kRadiusKey);
    BOOL sizeChanged = !CGSizeEqualToSize(rim.bounds.size, b.size);
    if (sizeChanged || !rm.path || lastR.doubleValue != radius) {
        rim.frame = b;
        rm.frame = rim.bounds;
        UIBezierPath *ring = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:radius];
        [ring appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, 1.0, 1.0)
                                                    cornerRadius:MAX(radius - 1.0, 0.0)]];
        rm.path = ring.CGPath;
        objc_setAssociatedObject(rim, &kRadiusKey, @(radius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [CATransaction commit];

    // bayangan lembut di bawah
    host.layer.shadowColor = UIColor.blackColor.CGColor;
    host.layer.shadowOpacity = 0.13;
    host.layer.shadowRadius = 16.0;
    host.layer.shadowOffset = CGSizeMake(0, 6);
    host.layer.shadowPath =
        [UIBezierPath bezierPathWithRoundedRect:host.bounds cornerRadius:radius].CGPath;
}

// Tombol bulat yang memasang ulang efek glass setiap layout.
@interface S26Button : UIButton
@property (nonatomic, weak) UIVisualEffectView *glass;
@end

@implementation S26Button
- (void)layoutSubviews {
    [super layoutSubviews];
    UIVisualEffectView *g = self.glass;
    if (g) S26ApplyGlass(self, g, self.bounds.size.height / 2.0);
}
@end

static void S26Press(UIView *v, BOOL down) {
    if (!v) return;
    [UIView animateWithDuration:down ? 0.16 : 0.34
                          delay:0
         usingSpringWithDamping:down ? 0.8 : 0.55
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        v.transform = down ? CGAffineTransformMakeScale(0.90, 0.90)
                           : CGAffineTransformIdentity;
    } completion:nil];
}

static UIButton *S26Circle(NSInteger tag, NSString *symbol) {
    S26Button *b = [S26Button buttonWithType:UIButtonTypeCustom];
    b.tag = tag;
    b.bounds = CGRectMake(0, 0, kRowH, kRowH);

    UIVisualEffectView *fx = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    fx.userInteractionEnabled = NO;
    fx.frame = CGRectMake(0, 0, kRowH, kRowH);
    [b addSubview:fx];
    b.glass = fx;
    S26ApplyGlass(b, fx, kRowH / 2.0);

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:17
                                                        weight:UIImageSymbolWeightSemibold];
    UIImageView *iv = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:symbol withConfiguration:cfg]];
    iv.tintColor = UIColor.labelColor;
    iv.contentMode = UIViewContentModeCenter;
    iv.frame = CGRectMake(0, 0, kRowH, kRowH);
    iv.userInteractionEnabled = NO;
    iv.tag = kIcon;
    [b addSubview:iv];

    __weak UIButton *wb = b;
    [b addAction:[UIAction actionWithHandler:^(UIAction *a) { S26Press(wb, YES); }]
        forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [b addAction:[UIAction actionWithHandler:^(UIAction *a) { S26Press(wb, NO); }]
        forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                         UIControlEventTouchCancel | UIControlEventTouchDragExit];
    return b;
}

#if kUseScrim
static UIView *S26EnsureScrim(UIView *s) {
    UIView *v = [s viewWithTag:kScrim];
    if (v) return v;
    UIVisualEffectView *fx = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    fx.tag = kScrim;
    fx.userInteractionEnabled = NO;
    CAGradientLayer *m = [CAGradientLayer layer];
    m.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor];
    m.locations = @[@0.0, @0.75];
    m.startPoint = CGPointMake(0.5, 0.0);
    m.endPoint = CGPointMake(0.5, 1.0);
    fx.layer.mask = m;
    [s insertSubview:fx atIndex:0];
    return fx;
}
#endif

// ---------------------------------------------------------------------------
// Aksi toolbar Safari
// ---------------------------------------------------------------------------
static void S26Collect(UIView *v, NSMutableArray *out) {
    for (UIView *sv in v.subviews) {
        if ([sv isKindOfClass:[UIControl class]]) [out addObject:sv];
        else S26Collect(sv, out);
    }
}

static NSArray *S26Controls(UIView *t) {
    NSMutableArray *c = [NSMutableArray array];
    S26Collect(t, c);
    [c sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = [a.superview convertPoint:a.center toView:nil].x;
        CGFloat bx = [b.superview convertPoint:b.center toView:nil].x;
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    return c;
}

static NSArray *S26Items(UIView *t) {
    if (![t respondsToSelector:@selector(items)]) return @[];
    NSArray *all = [(UIToolbar *)t items];
    NSMutableArray *r = [NSMutableArray array];
    for (UIBarButtonItem *it in all) {
        if (it.customView || it.image || it.title.length || it.action || it.primaryAction) {
            [r addObject:it];
        }
    }
    return r;
}

static void S26Fire(UIView *t, NSUInteger idx) {
    if (!t) return;
    NSArray *its = S26Items(t);
    if (idx < its.count) {
        UIBarButtonItem *it = its[idx];
        if (it.action) {
            [UIApplication.sharedApplication sendAction:it.action to:it.target from:it forEvent:nil];
            return;
        }
        SEL psel = NSSelectorFromString(@"performWithSender:target:");
        if (it.primaryAction && [it.primaryAction respondsToSelector:psel]) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(it.primaryAction, psel, it, nil);
            return;
        }
    }
    NSArray *c = S26Controls(t);
    if (idx < c.count) {
        [(UIControl *)c[idx] sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
}

static UIViewController *S26TopVC(UIView *v) {
    UIViewController *vc = v.window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static void S26ShowMore(UIView *t, UIView *source) {
    if (!t) return;
    UIViewController *top = S26TopVC(t);
    if (!top) return;
    NSArray *its = S26Items(t);
    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:nil
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles = @[@"Tab", @"Bookmark", @"Bagikan", @"Maju"];
    NSUInteger idxs[4] = {4, 3, 2, 1};
    for (int i = 0; i < 4; i++) {
        NSUInteger idx = idxs[i];
        __weak UIView *wt = t;
        UIAlertAction *act =
            [UIAlertAction actionWithTitle:titles[i]
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *a) {
                dispatch_async(dispatch_get_main_queue(), ^{ S26Fire(wt, idx); });
            }];
        if (idx < its.count) act.enabled = ((UIBarButtonItem *)its[idx]).enabled;
        [ac addAction:act];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Batal"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    ac.popoverPresentationController.sourceView = source;
    ac.popoverPresentationController.sourceRect = source.bounds;
    [top presentViewController:ac animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
// Sinkronisasi tombol bulat dan blur tepi bawah
// ---------------------------------------------------------------------------
static void S26Sync(UIView *t) {
    UIView *s = t.superview;
    if (!s || !t.window) return;

    UIButton *back = (UIButton *)[s viewWithTag:kBack];
    UIButton *more = (UIButton *)[s viewWithTag:kMore];

    if (!back) {
        back = S26Circle(kBack, @"chevron.left");
        __weak UIView *wt = t;
        [back addAction:[UIAction actionWithHandler:^(UIAction *a) { S26Fire(wt, 0); }]
            forControlEvents:UIControlEventTouchUpInside];
        [s addSubview:back];
    }
    if (!more) {
        more = S26Circle(kMore, @"ellipsis");
        __weak UIView *wt = t;
        __weak UIView *wm = more;
        [more addAction:[UIAction actionWithHandler:^(UIAction *a) { S26ShowMore(wt, wm); }]
            forControlEvents:UIControlEventTouchUpInside];
        [s addSubview:more];
    }

    NSArray *its = S26Items(t);
    CGFloat a = S26RealAlpha(t);
    BOOL vis = (!t.hidden && a > 0.05 && its.count == 5 &&
                t.frame.origin.y < s.bounds.size.height - 20.0);

    CGFloat y = t.frame.origin.y - kLift;
    CGPoint bc = CGPointMake(kSide + kRowH / 2.0, y + kRowH / 2.0);
    CGPoint mc = CGPointMake(s.bounds.size.width - kSide - kRowH / 2.0, y + kRowH / 2.0);
    if (!CGPointEqualToPoint(back.center, bc)) back.center = bc;
    if (!CGPointEqualToPoint(more.center, mc)) more.center = mc;

    NSArray *subs = s.subviews;
    if (subs.count < 2 || subs.lastObject != more || subs[subs.count - 2] != back) {
        [s bringSubviewToFront:back];
        [s bringSubviewToFront:more];
    }

    BOOL en = its.count ? ((UIBarButtonItem *)its.firstObject).enabled : YES;

    if (back.hidden == vis) back.hidden = !vis;
    if (more.hidden == vis) more.hidden = !vis;
    if (back.alpha != a) back.alpha = a;
    if (more.alpha != a) more.alpha = a;
    if (back.enabled != en) back.enabled = en;
    UIView *biv = [back viewWithTag:kIcon];
    CGFloat ia = en ? 1.0 : 0.4;
    if (biv && biv.alpha != ia) biv.alpha = ia;

#if kUseScrim
    UIView *scrim = S26EnsureScrim(s);
    CGRect sf = CGRectMake(0, s.bounds.size.height - kScrimH, s.bounds.size.width, kScrimH);
    if (!CGRectEqualToRect(scrim.frame, sf)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        scrim.frame = sf;
        scrim.layer.mask.frame = scrim.bounds;
        [CATransaction commit];
    }
    if (scrim.hidden == vis) scrim.hidden = !vis;
    CGFloat sa = a;
    if (scrim.alpha != sa) scrim.alpha = sa;
#endif
}

// ---------------------------------------------------------------------------
// Penanganan ketukan address bar
// ---------------------------------------------------------------------------
static CGPoint S26MapTap(CGPoint p) {
    if (CGRectIsEmpty(gNewCap) || CGRectIsEmpty(gOldCap)) return p;
    if (!CGRectContainsPoint(gNewCap, p)) return p;
    CGFloat sx = gOldCap.size.width / gNewCap.size.width;
    CGFloat sy = gOldCap.size.height / gNewCap.size.height;
    return CGPointMake(gOldCap.origin.x + (p.x - gNewCap.origin.x) * sx,
                       gOldCap.origin.y + (p.y - gNewCap.origin.y) * sy);
}

static BOOL S26ShouldMap(UIView *view) {
    if (!gInTap) return NO;
    if (!view) return YES;
    UIView *c = gColl;
    return (c && [c isDescendantOfView:view]);
}

static BOOL S26InSubControl(UIView *v) {
    for (UIView *x = v; x; x = x.superview) {
        if ([S26Name(x) isEqualToString:@"SFCapsuleNavigationBar"]) return NO;
        if ([x isKindOfClass:[UIControl class]]) return YES;
    }
    return NO;
}

static UIView *S26CenterNavBar(UIView *coll) {
    for (UIView *sv in coll.subviews) {
        if (![S26Name(sv) isEqualToString:@"SFCapsuleView"]) continue;
        if (fabs(sv.frame.origin.x - gNewCap.origin.x) > 2.0) continue;
        UIView *nb = S26Find(sv, @"SFCapsuleNavigationBar");
        if (nb) return nb;
    }
    return nil;
}

static BOOL S26TapURL(UIView *nb) {
    if (![nb respondsToSelector:@selector(delegate)]) return NO;
    id d = ((id (*)(id, SEL))objc_msgSend)(nb, @selector(delegate));
    SEL sel = NSSelectorFromString(@"navigationBarURLWasTapped:completionHandler:");
    if (!d || ![d respondsToSelector:sel]) return NO;
    void (^done)(void) = ^{};
    ((void (*)(id, SEL, id, id))objc_msgSend)(d, sel, nb, done);
    return YES;
}

// ---------------------------------------------------------------------------
// Styling pill address bar
// ---------------------------------------------------------------------------
static void S26StyleCapsule(UIView *c) {
    CGRect b = c.bounds;
    for (UIView *sv in c.subviews) {
        if (!CGRectEqualToRect(sv.frame, b)) sv.frame = b;
    }
    UIView *nb = S26Find(c, @"SFCapsuleNavigationBar");
    if (nb.superview && !CGRectEqualToRect(nb.frame, nb.superview.bounds)) {
        nb.frame = nb.superview.bounds;
    }
    for (UIView *sv in c.subviews) {
        if ([sv isKindOfClass:[UIVisualEffectView class]]) {
            S26ApplyGlass(c, (UIVisualEffectView *)sv, b.size.height / 2.0);
            break;
        }
    }
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------
%hook BrowserToolbar

- (void)layoutSubviews {
    %orig;
    UIView *t = (UIView *)self;
    gToolbar = t;
    gColl = t.superview;
    [(UIView *)self setAlpha:S26RealAlpha(t)];
    S26Sync(t);
    if (!gKicked && t.superview) {
        gKicked = YES;
        [t.superview setNeedsLayout];
    }
}

- (void)setAlpha:(CGFloat)a {
    objc_setAssociatedObject(self, &kAlphaKey, @(a), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *t = (UIView *)self;
    if (S26Items(t).count == 5) {
        %orig(0.0);
    } else {
        %orig(a);
    }
    if (t.window) S26Sync(t);
}

- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    %orig;
    UIView *t = (UIView *)self;
    [(UIView *)self setAlpha:S26RealAlpha(t)];
    if (t.window) S26Sync(t);
}

%end

%hook SFCapsuleCollectionView

- (void)_didReceiveTap:(id)g {
    UIView *self_ = (UIView *)self;
    CGPoint p = [(UIGestureRecognizer *)g locationInView:self_];
    if (!CGRectIsEmpty(gNewCap) && CGRectContainsPoint(gNewCap, p)) {
        UIView *hv = [self_ hitTest:p withEvent:nil];
        if (!S26InSubControl(hv)) {
            UIView *nb = S26CenterNavBar(self_);
            if (nb && S26TapURL(nb)) return;
        }
    }
    gInTap = YES;
    %orig;
    gInTap = NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = (UIView *)self;
    for (NSNumber *tg in @[@(kMore), @(kBack)]) {
        UIView *b = [v viewWithTag:tg.integerValue];
        if (b && b.superview == v && !b.hidden && b.alpha > 0.01) {
            CGPoint p = [v convertPoint:point toView:b];
            if (CGRectContainsPoint(CGRectInset(b.bounds, -6.0, -6.0), p)) {
                UIView *h = [b hitTest:p withEvent:event];
                return h ?: b;
            }
        }
    }
    for (UIView *sv in [v.subviews reverseObjectEnumerator]) {
        if (![S26Name(sv) isEqualToString:@"SFCapsuleView"]) continue;
        if (sv.hidden || sv.alpha < 0.01 || !sv.userInteractionEnabled) continue;
        if (CGRectContainsPoint(sv.frame, point)) {
            UIView *h = [sv hitTest:[v convertPoint:point toView:sv] withEvent:event];
            if (h) return h;
        }
    }
    return %orig;
}

- (void)layoutSubviews {
    %orig;
    UIView *v = (UIView *)self;
    for (UIView *sv in v.subviews) {
        if (sv.tag == kScrim) continue;
        NSString *n = S26Name(sv);
        if ([n isEqualToString:@"SFShadowView"] ||
            [n isEqualToString:@"UIVisualEffectView"] ||
            [n isEqualToString:@"_UIVisualEffectBackdropView"]) {
            sv.hidden = YES;
        }
    }
    UIView *t = gToolbar;
    if (t && t.superview == v) {
        for (UIView *sv in v.subviews) {
            if ([S26Name(sv) isEqualToString:@"SFCapsuleView"]) {
                [sv setFrame:sv.frame];
            }
        }
    }
}

%end

%hook SFCapsuleView

- (void)layoutSubviews {
    %orig;
    UIView *c = (UIView *)self;
    if (!CGRectIsEmpty(gNewCap) &&
        fabs(c.frame.origin.x - gNewCap.origin.x) < 1.0 &&
        fabs(c.frame.size.width - gNewCap.size.width) < 1.0 &&
        fabs(c.frame.size.height - gNewCap.size.height) < 1.0) {
        S26StyleCapsule(c);
    }
}

- (void)setFrame:(CGRect)f {
    CGRect inF = f;
    UIView *c = (UIView *)self;
    UIView *t = gToolbar;
    BOOL adjust = NO;
    if (t && t.superview && c.superview == t.superview &&
        !t.hidden && S26RealAlpha(t) > 0.05 && f.size.height >= 40.0 &&
        t.frame.origin.y < t.superview.bounds.size.height - 20.0 &&
        S26Items(t).count == 5 && S26Find(c, @"SFCapsuleNavigationBar")) {
        adjust = YES;
    }
    BOOL isCenter = NO;
    if (adjust) {
        CGFloat W = t.superview.bounds.size.width;
        CGFloat inset = kSide + kRowH + kGap;
        CGFloat newW = W - 2.0 * inset;
        CGFloat dx = inF.origin.x - (W - inF.size.width) / 2.0;
        f = CGRectMake(inset + dx * (W / (inF.size.width + 8.0)),
                       t.frame.origin.y - kLift, newW, kRowH);
        isCenter = (fabs(dx) < 2.0);
    }
    if (adjust && isCenter) {
        gOldCap = inF;
        gNewCap = f;
    } else if (!adjust && S26Find(c, @"SFCapsuleNavigationBar")) {
        gOldCap = CGRectZero;
        gNewCap = CGRectZero;
    }
    %orig(f);
    if (adjust) S26StyleCapsule(c);
}

%end

%hook TabOverview

- (void)layoutSubviews {
    %orig;
    UIView *v = (UIView *)self;
    for (UIView *sv in v.subviews) {
        if (![S26Name(sv) isEqualToString:@"UIVisualEffectView"]) continue;
        if (sv.frame.origin.y < v.bounds.size.height * 0.7) continue;
        if (sv.frame.size.height > 120.0) continue;
        if (sv.hidden && S26Find(sv, @"BarButton")) sv.hidden = NO;
    }
}

%end

%hook UIGestureRecognizer

- (CGPoint)locationInView:(UIView *)view {
    CGPoint p = %orig;
    if (S26ShouldMap(view)) return S26MapTap(p);
    return p;
}

- (CGPoint)locationOfTouch:(NSUInteger)touchIndex inView:(UIView *)view {
    CGPoint p = %orig;
    if (S26ShouldMap(view)) return S26MapTap(p);
    return p;
}

%end
