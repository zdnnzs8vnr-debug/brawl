#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach_time.h>
#import "BSConfig.h"
#import "BSVision.h"
#import "BSHUD.h"
#import "BSPanel.h"

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreateWithType(CFAllocatorRef, int, CFDictionaryRef);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef, IOHIDEventRef);
extern IOHIDEventRef IOHIDEventCreateDigitizerEvent(CFAllocatorRef, uint64_t, int, uint32_t, uint32_t,
    uint32_t, uint32_t, double, double, double, double, double, int, int, uint32_t);
extern IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(CFAllocatorRef, uint64_t, uint32_t, uint32_t,
    uint32_t, uint32_t, double, double, double, double, double, int, int, uint32_t);
extern void IOHIDEventAppendEvent(IOHIDEventRef, IOHIDEventRef, int);
extern void IOHIDEventSetIntegerValue(IOHIDEventRef, int, int);

static IOHIDEventSystemClientRef gHID;
static BSHUD *gHud;
static UIWindow *gWin;
static CFTimeInterval gFire, gDodgeT, gSup, gLockT;
static int gSide = 1;
static CGRect gLock;
static int gTries;

static void finger(int ph, CGPoint p, int id) {
    if (!gHID) gHID = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, 1, NULL);
    IOHIDEventRef h = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, mach_absolute_time(),
        0, 0, (uint32_t)id, (uint32_t)ph, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    IOHIDEventRef f = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, mach_absolute_time(),
        (uint32_t)id, (uint32_t)id, (uint32_t)ph, 0, p.x, p.y, 0, 0, 0, 0, 1, 0);
    IOHIDEventAppendEvent(h, f, 0);
    IOHIDEventSetIntegerValue(h, 0, 1);
    IOHIDEventSystemClientDispatchEvent(gHID, h);
}

static CGPoint atk(void) {
    CGSize s = UIScreen.mainScreen.bounds.size;
    return CGPointMake(s.width * 0.898, s.height * 0.792);
}
static CGPoint sup(void) {
    CGSize s = UIScreen.mainScreen.bounds.size;
    return CGPointMake(s.width * 0.755, s.height * 0.795);
}
static CGPoint joy(void) {
    CGSize s = UIScreen.mainScreen.bounds.size;
    return CGPointMake(s.width * 0.101, s.height * 0.796);
}

static void onTargets(NSArray *ts) {
    CGPoint me = BSVision.shared.selfPos;
    CFTimeInterval now = CACurrentMediaTime();

    gHud.me = me;
    gHud.targets = gESP ? ts : @[];
    gHud.stat = [NSString stringWithFormat:@"%.0f fps  %.1f ms",
                 BSVision.shared.fps, BSVision.shared.avgLatency * 1000];

    BSTarget best; BOOL has = NO; float bs = 1e9f;
    for (NSValue *v in ts) {
        BSTarget t; [v getValue:&t];
        float s;
        if (t.ghost) {
            s = 2.4f + (float)(now - t.seen);
        } else {
            if (t.dist > gRangeTiles * 0.96f) continue;
            s = t.dist;
        }
        if (now - gLockT < 0.35f && CGRectIntersectsRect(t.box, gLock)) s -= 1.6f;
        if (s < bs) { bs = s; best = t; has = YES; }
    }
    if (!has) return;

    if (gAim && now - gFire > gCooldown) {
        CGPoint a = atk();
        CGPoint tp = best.ghost
            ? CGPointMake(CGRectGetMidX(best.box), CGRectGetMidY(best.box))
            : CGPointMake(CGRectGetMidX(best.box) + best.vel.x * 0.09f,
                          CGRectGetMidY(best.box) + 10 + best.vel.y * 0.09f);
        float dx = tp.x - a.x, dy = tp.y - a.y;
        float n = sqrtf(dx * dx + dy * dy); if (n < 1) n = 1;
        float j = best.ghost ? gJitter * 2.5f : gJitter;
        CGPoint to = CGPointMake(a.x + dx / n * 128 + ((rand() % 200) / 100.0f - 1) * j,
                                 a.y + dy / n * 128 + ((rand() % 200) / 100.0f - 1) * j);
        finger(1, a, 0);
        finger(2, to, 0);
        gFire = now;
        gLock = best.box; gLockT = now;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 32000000), dispatch_get_main_queue(), ^{
            finger(4, to, 0);
        });
    }

    if (gSuper && !best.ghost && best.dist > 0 &&
        best.dist < gRangeTiles * 0.55f && now - gSup > 1.2f) {
        CGPoint s = sup();
        finger(1, s, 3);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20000000), dispatch_get_main_queue(), ^{
            finger(4, s, 3);
        });
        gSup = now;
    }

    if (gDodge && best.dist > 0 && best.dist < 6 && now - gDodgeT > 0.42f) {
        CGPoint c = joy();
        float dx = CGRectGetMidX(best.box) - me.x, dy = CGRectGetMidY(best.box) - me.y;
        float n = sqrtf(dx * dx + dy * dy); if (n < 1) n = 1;
        CGPoint to = CGPointMake(c.x - dy / n * 105 * gSide, c.y + dx / n * 105 * gSide);
        finger(1, c, 1);
        finger(2, to, 1);
        gSide *= -1;
        gDodgeT = now;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 240000000), dispatch_get_main_queue(), ^{
            finger(4, to, 1);
        });
    }
}

static void boot(UIWindow *k) {
    cfgLoad();
    gWin = [[UIWindow alloc] initWithFrame:k.bounds];
    gWin.windowLevel = UIWindowLevelAlert - 1;
    gWin.backgroundColor = UIColor.clearColor;
    gWin.userInteractionEnabled = NO;

    gHud = [[BSHUD alloc] initWithFrame:k.bounds];
    gHud.backgroundColor = UIColor.clearColor;
    gWin.rootViewController = [UIViewController new];
    gWin.rootViewController.view = gHud;
    gWin.hidden = NO;

    [BSPanel attachTo:k];
    [BSVision.shared startWithCallback:^(NSArray *t) { onTargets(t); }];
}

static void bootWhenReady(void) {
    UIWindow *k = UIApplication.sharedApplication.keyWindow;
    if (!k && ++gTries < 80) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500000000), dispatch_get_main_queue(), ^{
            bootWhenReady();
        });
        return;
    }
    if (!k) return;
    boot(k);
}

__attribute__((constructor)) static void bsvx_init(void) {
    if (![[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"com.supercell.laser"]) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500000000), dispatch_get_main_queue(), ^{
        bootWhenReady();
    });
}
