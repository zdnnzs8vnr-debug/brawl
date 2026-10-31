#import "BSVision.h"
#import "BSConfig.h"
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>

extern void CARenderServerRenderDisplay(mach_port_t server, CFStringRef name, CGContextRef ctx);

#define BLK 4
#define MAXT 64

static CGColorSpaceRef gCS;

@interface BSVision ()
- (NSArray *)analyze:(int)idx;
@end

@implementation BSVision {
    uint8_t *_buf[3];
    CGContextRef _ctx[3];
    int _cur;
    size_t _w, _h, _bw, _bh;
    uint8_t *_prev, *_red, *_grn, *_dif, *_mark;
    NSMutableArray *_ghosts;
    CADisplayLink *_link;
    dispatch_queue_t _q;
    void (^_cb)(NSArray *);
    CFTimeInterval _calStart, _lastCap;
    float _latAvg, _calMax, _fps;
}

+ (instancetype)shared {
    static BSVision *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [BSVision new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _ghosts = [NSMutableArray array];
        _q = dispatch_queue_create("bsvx.vision", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_q, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));
        if (!gCS) gCS = CGColorSpaceCreateDeviceRGB();
    }
    return self;
}

- (CGPoint)selfPos {
    CGSize s = UIScreen.mainScreen.bounds.size;
    return CGPointMake(s.width * 0.5, s.height * 0.62);
}

- (float)avgLatency { return _latAvg > 0 ? _latAvg : 0.012f; }
- (float)fps { return _fps; }

- (void)startWithCallback:(void (^)(NSArray *))cb {
    _cb = [cb copy];
    CGSize s = UIScreen.mainScreen.bounds.size;
    _w = 240;
    _h = (size_t)(240 * s.height / s.width);
    _bw = _w / BLK;
    _bh = _h / BLK;
    size_t px = _w * _h, bl = _bw * _bh;

    for (int i = 0; i < 3; i++) {
        _buf[i] = calloc(px * 4, 1);
        _ctx[i] = CGBitmapContextCreate(_buf[i], _w, _h, 8, _w * 4, gCS,
            kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    }
    _prev = calloc(px, 1);
    _red  = calloc(bl, 1);
    _grn  = calloc(bl, 1);
    _dif  = calloc(bl, 1);
    _mark = calloc(bl, 1);

    __weak typeof(self) wself = self;
    id tgt = [NSBlockOperation blockOperationWithBlock:^{ [wself frame]; }];
    _link = [CADisplayLink displayLinkWithTarget:tgt selector:@selector(main)];
    _link.preferredFramesPerSecond = 60;
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)frame {
    CFTimeInterval now = CACurrentMediaTime();
    float dt = (float)(now - _lastCap);
    if (dt < 0.016f) return;
    _fps = _fps * 0.9f + (1.0f / MAX(dt, 0.001f)) * 0.1f;
    _lastCap = now;

    _cur = (_cur + 1) % 3;
    const int idx = _cur;
    CARenderServerRenderDisplay(0, CFSTR("LCD"), _ctx[idx]);

    __weak typeof(self) wself = self;
    dispatch_async(_q, ^{
        NSArray *r = [wself analyze:idx];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) sself = wself;
            if (sself && sself->_cb) sself->_cb(r);
        });
    });
}

- (NSArray *)analyze:(int)idx {
    CFTimeInterval t0 = CACurrentMediaTime();
    uint8_t *buf = _buf[idx];
    size_t bl = _bw * _bh;
    memset(_red, 0, bl); memset(_grn, 0, bl); memset(_dif, 0, bl); memset(_mark, 0, bl);

    const size_t TOP = _h * 7 / 100, BOT = _h * 86 / 100;

    for (size_t y = 0; y < _h; y++) {
        const uint8_t *row = buf + y * _w * 4;
        uint8_t *prow = _prev + y * _w;
        size_t br = (y / BLK) * _bw;
        BOOL hud = (y < TOP || y > BOT);
        for (size_t x = 0; x < _w; x++) {
            uint8_t b = row[x * 4], g = row[x * 4 + 1], r = row[x * 4 + 2];
            int gray = (r * 77 + g * 151 + b * 28) >> 8;
            int d = abs(gray - prow[x]);
            prow[x] = (uint8_t)gray;
            size_t bi = br + (x / BLK);
            if (!hud && r > 145 && g < 105 && b < 105 && r - g > 55) _red[bi]++;
            if (g > 82 && g - r > 15 && g - b > 8) _grn[bi]++;
            if (d > 20) _dif[bi]++;
        }
    }

    const int need = BLK * BLK;
    const float sc = UIScreen.mainScreen.bounds.size.width / (float)_w;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:MAXT];
    CFTimeInterval now = CACurrentMediaTime();

    for (size_t b = 0; b < bl && out.count < MAXT; b++) {
        if (_mark[b] || _red[b] < need * 0.45f) continue;

        int minx = 1 << 20, miny = 1 << 20, maxx = 0, maxy = 0, cnt = 0;
        size_t st[512]; int sp = 0;
        st[sp++] = b; _mark[b] = 1;

        while (sp) {
            size_t c = st[--sp];
            int cx = (int)(c % _bw), cy = (int)(c / _bw);
            if (cx < minx) minx = cx;
            if (cy < miny) miny = cy;
            if (cx > maxx) maxx = cx;
            if (cy > maxy) maxy = cy;
            cnt++;
            for (int dy = -1; dy <= 1; dy++) {
                for (int dx = -1; dx <= 1; dx++) {
                    int nx = cx + dx, ny = cy + dy;
                    if (nx < 0 || ny < 0 || nx >= (int)_bw || ny >= (int)_bh) continue;
                    size_t nb = (size_t)ny * _bw + (size_t)nx;
                    if (!_mark[nb] && _red[nb] >= need * 0.45f) {
                        _mark[nb] = 1;
                        if (sp < 512) st[sp++] = nb;
                    }
                }
            }
        }

        float bw = (float)(maxx - minx + 1), bh = (float)(maxy - miny + 1);
        if (cnt < 2 || bw < 2.5f || bw / bh > 34 || bw > 64) continue;

        BSTarget t;
        t.box = CGRectMake(minx * BLK * sc, miny * BLK * sc, bw * BLK * sc, bh * BLK * sc);
        t.dist = gCRange > 1 ? gCRange / (bw * BLK) : 0;
        t.ghost = NO; t.seen = now; t.vel = CGPointZero;
        [out addObject:[NSValue valueWithBytes:&t objCType:@encode(BSTarget)]];
    }

    for (size_t b = 0; b < bl; b++) {
        if (_dif[b] < need * 0.6f || _grn[b] < need * 0.4f) continue;
        int cx = (int)(b % _bw), cy = (int)(b / _bw);
        CGPoint p = CGPointMake(cx * BLK * sc, cy * BLK * sc);
        [_ghosts addObject:@[@(p.x), @(p.y), @(now)]];
        if (_ghosts.count > 300) [_ghosts removeObjectAtIndex:0];
    }

    NSMutableArray *keep = [NSMutableArray array];
    for (NSArray *g in _ghosts) {
        CFTimeInterval ts = [g[2] doubleValue];
        if (now - ts > 2.5) continue;
        [keep addObject:g];
        BSTarget t;
        t.box = CGRectMake([g[0] floatValue], [g[1] floatValue], 1, 1);
        t.dist = -1; t.ghost = YES; t.seen = ts; t.vel = CGPointZero;
        [out addObject:[NSValue valueWithBytes:&t objCType:@encode(BSTarget)]];
    }
    _ghosts = keep;

    if (self.calibrating) {
        if (!_calStart) { _calStart = now; _calMax = 0; }
        for (NSValue *v in out) {
            BSTarget t; [v getValue:&t];
            if (!t.ghost && t.box.size.width > _calMax) _calMax = t.box.size.width;
        }
        if (now - _calStart > 3.0) {
            if (_calMax > 5) { gCRange = gRangeTiles * (_calMax / sc); cfgSave(); }
            self.calibrating = NO;
            _calStart = 0;
        }
    }

    float ms = (float)(CACurrentMediaTime() - t0);
    _latAvg = _latAvg * 0.9f + ms * 0.1f;
    return out;
}
@end
