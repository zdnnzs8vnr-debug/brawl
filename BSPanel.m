#import "BSPanel.h"
#import "BSConfig.h"
#import "BSVision.h"

@implementation BSPanel

+ (void)attachTo:(UIView *)host {
    static BSPanel *p; static dispatch_once_t o;
    dispatch_once(&o, ^{
        p = [[BSPanel alloc] initWithFrame:CGRectMake(12, 64, 176, 268)];
        p.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
        p.layer.cornerRadius = 12;
        [p build];
        [host addSubview:p];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 7000000000), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{ p.alpha = 0.28; }];
        });
    });
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)e { self.alpha = 1.0; }

- (void)paint:(UIButton *)b on:(BOOL)on title:(NSString *)t {
    [b setTitle:[NSString stringWithFormat:@"%@ %@", on ? @"[ON ]" : @"[OFF]", t]
       forState:UIControlStateNormal];
    [b setTitleColor:(on ? UIColor.greenColor : UIColor.grayColor) forState:UIControlStateNormal];
}

- (void)row:(NSString *)title y:(CGFloat)y on:(BOOL)on tag:(int)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(8, y, 160, 28);
    b.tag = tag;
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    [self paint:b on:on title:title];
}

- (void)tap:(UIButton *)b {
    switch (b.tag) {
        case 0: gAim = !gAim;       [self paint:b on:gAim    title:@"Aimbot"];     break;
        case 1: gESP = !gESP;       [self paint:b on:gESP    title:@"ESP"];        break;
        case 2: gTracer = !gTracer; [self paint:b on:gTracer title:@"Linee"];      break;
        case 3: gDist = !gDist;     [self paint:b on:gDist   title:@"Distanza"];   break;
        case 4: gDodge = !gDodge;   [self paint:b on:gDodge  title:@"Auto-dodge"]; break;
        case 5: gSuper = !gSuper;   [self paint:b on:gSuper  title:@"Auto-super"]; break;
    }
    cfgSave();
}

- (void)build {
    [self row:@"Aimbot"     y:6   on:gAim    tag:0];
    [self row:@"ESP"        y:34  on:gESP    tag:1];
    [self row:@"Linee"      y:62  on:gTracer tag:2];
    [self row:@"Distanza"   y:90  on:gDist   tag:3];
    [self row:@"Auto-dodge" y:118 on:gDodge  tag:4];
    [self row:@"Auto-super" y:146 on:gSuper  tag:5];

    UIButton *c = [UIButton buttonWithType:UIButtonTypeSystem];
    c.frame = CGRectMake(8, 178, 160, 30);
    [c setTitle:@"CALIBRA RANGE" forState:UIControlStateNormal];
    [c setTitleColor:UIColor.cyanColor forState:UIControlStateNormal];
    [c addTarget:self action:@selector(cal) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:c];

    UILabel *h = [[UILabel alloc] initWithFrame:CGRectMake(8, 210, 160, 50)];
    h.text = @"Nemico sul bordo del cerchio, poi CALIBRA";
    h.numberOfLines = 3;
    h.font = [UIFont systemFontOfSize:9.5];
    h.textColor = UIColor.lightGrayColor;
    [self addSubview:h];
}

- (void)cal { BSVision.shared.calibrating = YES; }
@end
