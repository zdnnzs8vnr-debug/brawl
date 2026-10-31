#import "BSHUD.h"
#import "BSVision.h"
#import "BSConfig.h"
#import <QuartzCore/QuartzCore.h>

@implementation BSHUD

- (void)setTargets:(NSArray *)t { _targets = t; [self setNeedsDisplay]; }
- (void)setStat:(NSString *)s { _stat = s; [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    NSDictionary *attr = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:10],
                           NSForegroundColorAttributeName:UIColor.yellowColor};

    for (NSValue *v in self.targets) {
        BSTarget t; [v getValue:&t];

        if (t.ghost) {
            float a = MAX(0.15, 1.0 - (CACurrentMediaTime() - t.seen) / 2.5);
            CGContextSetLineWidth(c, 1.4);
            CGContextSetRGBStrokeColor(c, 1, 0, 1, a);
            CGContextStrokeRect(c, CGRectInset(t.box, -9, -9));
            continue;
        }

        float k = MIN(1.0, t.dist / MAX(gRangeTiles, 1.0));
        CGRect b = CGRectInset(t.box, -4, -7);

        CGContextSetLineWidth(c, 1.4);
        CGContextSetRGBStrokeColor(c, k, 1.0 - k * 0.85, 0.15, 0.95);
        CGContextStrokeRect(c, b);

        CGContextSetLineWidth(c, 2.6);
        float L = 6;
        CGPoint pts[4] = {{b.origin.x, b.origin.y},
                          {b.origin.x + b.size.width, b.origin.y},
                          {b.origin.x + b.size.width, b.origin.y + b.size.height},
                          {b.origin.x, b.origin.y + b.size.height}};
        for (int i = 0; i < 4; i++) {
            CGPoint p = pts[i];
            float sx = (i == 0 || i == 3) ? L : -L;
            float sy = (i < 2) ? L : -L;
            CGContextMoveToPoint(c, p.x, p.y);
            CGContextAddLineToPoint(c, p.x + sx, p.y);
            CGContextMoveToPoint(c, p.x, p.y);
            CGContextAddLineToPoint(c, p.x, p.y + sy);
        }
        CGContextStrokePath(c);

        if (gTracer) {
            CGContextSetLineWidth(c, 1.0);
            CGContextSetRGBStrokeColor(c, k, 1.0 - k * 0.85, 0.15, 0.45);
            CGContextMoveToPoint(c, self.me.x, self.me.y);
            CGContextAddLineToPoint(c, CGRectGetMidX(b), CGRectGetMidY(b));
            CGContextStrokePath(c);
        }

        if (gDist && t.dist > 0) {
            NSString *s = [NSString stringWithFormat:@"%.1fm", t.dist];
            [s drawAtPoint:CGPointMake(b.origin.x, b.origin.y - 13) withAttributes:attr];
        }
    }

    if (self.stat) {
        [self.stat drawAtPoint:CGPointMake(self.bounds.size.width - 96, 8)
                withAttributes:@{NSFontAttributeName:[UIFont monospacedSystemFontOfSize:10
                                                                              weight:UIFontWeightMedium],
                                 NSForegroundColorAttributeName:UIColor.greenColor}];
    }
}
@end
